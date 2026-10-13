// The "goo" look for the liquid layers, on the GPU.
//
// The shapes are still drawn with Canvas 2D, into an offscreen canvas at 1 px per point.
// WebGL then blurs them and thresholds the alpha: the same math as the original SVG filter
// (feGaussianBlur stdDeviation 7, then alpha × 22 − 9). WebKit runs SVG filters on the CPU
// at Retina resolution every frame, which held the show to about 14 fps; here the blur runs
// at 1x and only the final threshold pass runs at Retina, so edges stay crisp.
//
// Without WebGL (or with ?goo=svg, for comparing the two) the layer falls back to the SVG
// filter on the visible canvas.
import { type CanvasRegion, clear, retinaScale, setupCanvas, sizeCanvas } from "./canvas";

/** Blur of the goo, in points (the SVG filter's stdDeviation). */
const BLUR = 7;
/** Alpha threshold, a' = a × GAIN + OFFSET (the SVG filter's color matrix row). */
const GAIN = 22;
const OFFSET = -9;
/** Pixels per point of the offscreen shapes. The blur erases anything finer. */
const SOURCE_SCALE = 1;

export type LiquidColor = readonly [r: number, g: number, b: number];

const VERTEX = `
attribute vec2 a_pos;
uniform float u_flipY;
varying vec2 v_uv;
void main() {
  v_uv = vec2(a_pos.x, a_pos.y * u_flipY) * 0.5 + 0.5;
  gl_Position = vec4(a_pos, 0.0, 1.0);
}`;

const blurFragment = (taps: number) => `
precision highp float;
#define TAPS ${taps}
uniform sampler2D u_tex;
uniform vec2 u_step;
uniform float u_offsets[TAPS];
uniform float u_weights[TAPS];
varying vec2 v_uv;
void main() {
  float a = texture2D(u_tex, v_uv).a * u_weights[0];
  for (int i = 1; i < TAPS; i++) {
    vec2 o = u_step * u_offsets[i];
    a += (texture2D(u_tex, v_uv + o).a + texture2D(u_tex, v_uv - o).a) * u_weights[i];
  }
  gl_FragColor = vec4(a);
}`;

const THRESHOLD_FRAGMENT = `
precision highp float;
uniform sampler2D u_tex;
uniform vec3 u_color;
uniform vec2 u_gain;
varying vec2 v_uv;
void main() {
  float a = clamp(texture2D(u_tex, v_uv).a * u_gain.x + u_gain.y, 0.0, 1.0);
  gl_FragColor = vec4(u_color * a, a);
}`;

/**
 * Gaussian taps for one blur direction, paired so each bilinear fetch covers two texels.
 * Index 0 is the center; the others are sampled on both sides.
 */
export function gaussianTaps(sigma: number): { offsets: Float32Array; weights: Float32Array } {
  const radius = Math.ceil(sigma * 3);
  const w: number[] = [];
  for (let i = 0; i <= radius; i++) w.push(Math.exp(-(i * i) / (2 * sigma * sigma)));
  const total = w.reduce((sum, v, i) => sum + (i === 0 ? v : 2 * v), 0);
  const norm = w.map((v) => v / total);
  const offsets = [0];
  const weights = [norm[0] as number];
  for (let i = 1; i <= radius; i += 2) {
    const a = norm[i] as number;
    const b = norm[i + 1] ?? 0;
    offsets.push((i * a + (i + 1) * b) / (a + b));
    weights.push(a + b);
  }
  return { offsets: new Float32Array(offsets), weights: new Float32Array(weights) };
}

function compile(gl: WebGLRenderingContext, vertex: string, fragment: string): WebGLProgram {
  const program = gl.createProgram();
  for (const [type, source] of [
    [gl.VERTEX_SHADER, vertex],
    [gl.FRAGMENT_SHADER, fragment],
  ] as const) {
    const shader = gl.createShader(type);
    if (!shader) throw new Error("createShader failed");
    gl.shaderSource(shader, source);
    gl.compileShader(shader);
    if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS))
      throw new Error(gl.getShaderInfoLog(shader) ?? "shader error");
    gl.attachShader(program, shader);
  }
  gl.bindAttribLocation(program, 0, "a_pos");
  gl.linkProgram(program);
  if (!gl.getProgramParameter(program, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(program) ?? "link error");
  return program;
}

function texture(gl: WebGLRenderingContext): WebGLTexture {
  const tex = gl.createTexture();
  gl.bindTexture(gl.TEXTURE_2D, tex);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
  gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
  return tex;
}

/** Blur (horizontal, then vertical) at source size, then threshold into the visible canvas. */
class GooRenderer {
  private readonly blur: WebGLProgram;
  private readonly threshold: WebGLProgram;
  private readonly source: WebGLTexture;
  private readonly passes: [WebGLTexture, WebGLTexture];
  private readonly targets: [WebGLFramebuffer, WebGLFramebuffer];
  private width = 0;
  private height = 0;

  constructor(
    private readonly gl: WebGLRenderingContext,
    color: LiquidColor,
  ) {
    const { offsets, weights } = gaussianTaps(BLUR * SOURCE_SCALE);
    this.blur = compile(gl, VERTEX, blurFragment(offsets.length));
    this.threshold = compile(gl, VERTEX, THRESHOLD_FRAGMENT);

    gl.useProgram(this.blur);
    gl.uniform1i(gl.getUniformLocation(this.blur, "u_tex"), 0);
    gl.uniform1fv(gl.getUniformLocation(this.blur, "u_offsets"), offsets);
    gl.uniform1fv(gl.getUniformLocation(this.blur, "u_weights"), weights);
    gl.uniform1f(gl.getUniformLocation(this.blur, "u_flipY"), 1);
    gl.useProgram(this.threshold);
    gl.uniform1i(gl.getUniformLocation(this.threshold, "u_tex"), 0);
    gl.uniform3f(gl.getUniformLocation(this.threshold, "u_color"), ...color);
    gl.uniform2f(gl.getUniformLocation(this.threshold, "u_gain"), GAIN, OFFSET);
    // Canvas row 0 is the top of the texture; the screen's top is clip y = +1.
    gl.uniform1f(gl.getUniformLocation(this.threshold, "u_flipY"), -1);

    // One triangle that covers the whole viewport.
    gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer());
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
    gl.enableVertexAttribArray(0);
    gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);

    gl.disable(gl.BLEND);
    gl.disable(gl.DEPTH_TEST);
    // Canvas pixels are already premultiplied; taking them as-is avoids a conversion on upload.
    gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);

    this.source = texture(gl);
    this.passes = [texture(gl), texture(gl)];
    this.targets = this.passes.map((tex) => {
      const fb = gl.createFramebuffer();
      gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
      gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, tex, 0);
      return fb;
    }) as [WebGLFramebuffer, WebGLFramebuffer];
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
  }

  render(shapes: HTMLCanvasElement): void {
    const gl = this.gl;
    if (gl.isContextLost()) return;
    const { width, height } = shapes;
    if (width !== this.width || height !== this.height) {
      this.width = width;
      this.height = height;
      for (const tex of this.passes) {
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, width, height, 0, gl.RGBA, gl.UNSIGNED_BYTE, null);
      }
    }
    gl.activeTexture(gl.TEXTURE0);
    gl.bindTexture(gl.TEXTURE_2D, this.source);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, shapes);

    gl.useProgram(this.blur);
    const step = gl.getUniformLocation(this.blur, "u_step");
    gl.viewport(0, 0, width, height);
    // Horizontal: shapes -> pass 0.
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.targets[0]);
    gl.uniform2f(step, 1 / width, 0);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
    // Vertical: pass 0 -> pass 1.
    gl.bindFramebuffer(gl.FRAMEBUFFER, this.targets[1]);
    gl.bindTexture(gl.TEXTURE_2D, this.passes[0]);
    gl.uniform2f(step, 0, 1 / height);
    gl.drawArrays(gl.TRIANGLES, 0, 3);

    // Threshold: pass 1 -> screen, at the visible canvas's (Retina) size.
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.useProgram(this.threshold);
    gl.bindTexture(gl.TEXTURE_2D, this.passes[1]);
    gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
    gl.drawArrays(gl.TRIANGLES, 0, 3);
  }

  clear(): void {
    const gl = this.gl;
    if (gl.isContextLost()) return;
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
    gl.clearColor(0, 0, 0, 0);
    gl.clear(gl.COLOR_BUFFER_BIT);
  }
}

/** True when the page asks for the old SVG filter (?goo=svg), to compare the two. */
const forceSvg = new URLSearchParams(location.search).get("goo") === "svg";

/**
 * One liquid layer (the black island or the white blob). Draw this frame's shapes into
 * `setup`'s context, in screen points, then call `present`.
 */
export class LiquidLayer {
  private static readonly layers = new WeakMap<HTMLCanvasElement, LiquidLayer>();

  /** The layer for a page canvas, created on first use and reused by later shows. */
  static for(canvas: HTMLCanvasElement, color: LiquidColor): LiquidLayer {
    let layer = LiquidLayer.layers.get(canvas);
    if (!layer) {
      layer = new LiquidLayer(canvas, color);
      LiquidLayer.layers.set(canvas, layer);
    }
    return layer;
  }

  /** Clears a canvas's layer, if it has one (an unused canvas is already empty). */
  static clear(canvas: HTMLCanvasElement): void {
    LiquidLayer.layers.get(canvas)?.clear();
  }

  private canvas: HTMLCanvasElement;
  private readonly gpu: GooRenderer | null = null;
  private readonly shapes: HTMLCanvasElement | null = null;
  private ctx: CanvasRenderingContext2D | null = null;
  private empty = true;

  private constructor(canvas: HTMLCanvasElement, color: LiquidColor) {
    this.canvas = canvas;
    if (forceSvg) {
      canvas.classList.add("svg-goo");
      return;
    }
    const gl = canvas.getContext("webgl", {
      alpha: true,
      premultipliedAlpha: true,
      antialias: false,
      depth: false,
      stencil: false,
    });
    try {
      if (!gl) throw new Error("WebGL unavailable");
      this.gpu = new GooRenderer(gl, color);
      this.shapes = document.createElement("canvas");
    } catch (error) {
      console.warn("[island] liquid layer falls back to the SVG filter:", error);
      // A canvas that already has a WebGL context can't give a 2D one: swap in a fresh element.
      if (gl) {
        const fresh = canvas.cloneNode(false) as HTMLCanvasElement;
        canvas.replaceWith(fresh);
        this.canvas = fresh;
      }
      this.canvas.classList.add("svg-goo");
    }
  }

  /** Sizes the layer to the show's region; returns the 2D context to draw the shapes in. */
  setup(region: CanvasRegion, padTop: number): CanvasRenderingContext2D {
    if (this.gpu && this.shapes) {
      sizeCanvas(this.canvas, region, padTop, retinaScale());
      this.ctx = setupCanvas(this.shapes, region, padTop, SOURCE_SCALE);
    } else {
      this.ctx = setupCanvas(this.canvas, region, padTop);
    }
    this.empty = true;
    this.gpu?.clear();
    return this.ctx;
  }

  /** Shows this frame's shapes. Pass `empty` when nothing was drawn, so idle frames cost nothing. */
  present(empty = false): void {
    if (!this.gpu || !this.shapes) return; // the SVG filter applies itself
    if (empty) {
      if (!this.empty) this.gpu.clear();
    } else {
      this.gpu.render(this.shapes);
    }
    this.empty = empty;
  }

  clear(): void {
    if (this.gpu) {
      this.gpu.clear();
      this.empty = true;
    } else if (this.ctx) {
      clear(this.ctx);
    }
  }
}
