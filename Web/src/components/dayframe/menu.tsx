import { AnimatePresence, motion } from "motion/react";
import { type KeyboardEvent as ReactKeyboardEvent, type ReactNode, useEffect, useId, useRef, useState } from "react";
import { duration, ease } from "@/lib/motion";
import { cn } from "@/lib/utils";

export interface MenuItem {
  id: string;
  label: string;
  checked?: boolean;
  onSelect: () => void;
}

export interface MenuSection {
  title: string;
  items: MenuItem[];
}

interface MenuProps {
  label: string;
  trigger: ReactNode;
  sections: MenuSection[];
}

/** A small popover menu that grows from its button. Esc or a click outside closes it. */
export function Menu({ label, trigger, sections }: MenuProps) {
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLDivElement>(null);
  const button = useRef<HTMLButtonElement>(null);
  const menuId = useId();

  useEffect(() => {
    if (!open) return;
    const onPointer = (e: PointerEvent) => {
      if (!root.current?.contains(e.target as Node)) setOpen(false);
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setOpen(false);
        button.current?.focus();
      }
    };
    document.addEventListener("pointerdown", onPointer);
    document.addEventListener("keydown", onKey);
    root.current?.querySelector<HTMLElement>('[role^="menuitem"]')?.focus();
    return () => {
      document.removeEventListener("pointerdown", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const onMenuKey = (e: ReactKeyboardEvent) => {
    if (e.key !== "ArrowDown" && e.key !== "ArrowUp") return;
    e.preventDefault();
    const items = [...(root.current?.querySelectorAll<HTMLElement>('[role^="menuitem"]') ?? [])];
    const at = items.indexOf(document.activeElement as HTMLElement);
    const next = e.key === "ArrowDown" ? (at + 1) % items.length : (at - 1 + items.length) % items.length;
    items[next]?.focus();
  };

  return (
    <div ref={root} className="relative">
      <button
        ref={button}
        type="button"
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-controls={open ? menuId : undefined}
        onClick={() => setOpen((v) => !v)}
        className="grid size-[34px] place-items-center rounded-full border border-control-border bg-control text-control-text shadow-[inset_0_0_4px_var(--df-control-glow)]"
      >
        {trigger}
      </button>
      <AnimatePresence>
        {open ? (
          <motion.div
            id={menuId}
            role="menu"
            aria-label={label}
            onKeyDown={onMenuKey}
            initial={{ opacity: 0, scale: 0.94, y: -4 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
            exit={{ opacity: 0, scale: 0.97, transition: { duration: duration.quick } }}
            transition={{ duration: duration.base, ease: ease.outQuart }}
            style={{ transformOrigin: "top right" }}
            className="absolute top-[42px] right-0 z-20 w-60 rounded-xl border border-popover-border bg-popover p-1.5 shadow-[0_12px_32px_rgba(0,0,0,0.18)] backdrop-blur-xl"
          >
            {sections.map((section, s) => (
              <div key={section.title} role="group" aria-label={section.title} className={cn(s > 0 && "mt-1 border-t border-popover-border pt-1")}>
                <p className="px-2.5 pt-1.5 pb-1 text-[11px] font-semibold text-ink-muted">{section.title}</p>
                {section.items.map((item) => (
                  <button
                    key={item.id}
                    type="button"
                    role={item.checked === undefined ? "menuitem" : "menuitemradio"}
                    aria-checked={item.checked}
                    tabIndex={-1}
                    onClick={() => {
                      setOpen(false);
                      item.onSelect();
                    }}
                    className="flex w-full items-center justify-between rounded-lg px-2.5 py-1.5 text-left text-[13px] text-ink outline-none hover:bg-soft focus-visible:bg-soft"
                  >
                    {item.label}
                    {item.checked ? <span aria-hidden className="size-1.5 rounded-full bg-accent" /> : null}
                  </button>
                ))}
              </div>
            ))}
          </motion.div>
        ) : null}
      </AnimatePresence>
    </div>
  );
}
