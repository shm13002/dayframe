// Canvas sizing shared by the engine's 2D layer and the liquid layers.

/** The part of the screen the island can ever cover, in screen points. */
export interface CanvasRegion {
  x: number;
  w: number;
  h: number;
}

/** Pixels per point for crisp drawing (capped at 2). */
export function retinaScale(): number {
  return Math.min(2, window.devicePixelRatio || 1);
}

/** Sets a canvas's pixel size (`scale` pixels per point) and its on-screen box. `padTop` extends it above the screen edge. */
export function sizeCanvas(canvas: HTMLCanvasElement, region: CanvasRegion, padTop: number, scale: number): void {
  const h = region.h + padTop;
  canvas.width = Math.round(region.w * scale);
  canvas.height = Math.round(h * scale);
  canvas.style.width = `${region.w}px`;
  canvas.style.height = `${h}px`;
  canvas.style.left = `${region.x}px`;
}

/**
 * Sizes a canvas to the region and maps its drawing space to screen points,
 * so all drawing code can use screen coordinates.
 */
export function setupCanvas(
  canvas: HTMLCanvasElement,
  region: CanvasRegion,
  padTop: number,
  scale = retinaScale(),
): CanvasRenderingContext2D {
  sizeCanvas(canvas, region, padTop, scale);
  const ctx = canvas.getContext("2d");
  if (!ctx) throw new Error("2D canvas unavailable");
  ctx.setTransform(scale, 0, 0, scale, -region.x * scale, 0);
  return ctx;
}

export function clear(ctx: CanvasRenderingContext2D): void {
  ctx.save();
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.clearRect(0, 0, ctx.canvas.width, ctx.canvas.height);
  ctx.restore();
}
