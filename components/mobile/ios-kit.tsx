"use client";

import type { ComponentType, ReactNode } from "react";
import { ArrowUpRight, Check, ChevronLeft, ChevronRight } from "lucide-react";

/**
 * The iOS control vocabulary.
 *
 * These are not restyled Web components. A grouped inset list, a 52 pt row and
 * a 51×31 pt switch are iOS controls with their own metrics, and the packaged
 * app is built from them so it reads as an app rather than as the site in a
 * WebView. Colour, radius and type come from the tokens in `globals.css`.
 */

type Icon = ComponentType<{ className?: string; strokeWidth?: number }>;

export function IosGroup({
  title,
  note,
  children,
  className = "",
}: {
  title?: string;
  note?: string;
  children: ReactNode;
  className?: string;
}) {
  return (
    <div className={className}>
      {title && <div className="ios-group-title">{title}</div>}
      <div className="ios-group">{children}</div>
      {note && <p className="ios-group-note">{note}</p>}
    </div>
  );
}

interface RowProps {
  icon?: Icon;
  label: ReactNode;
  /** Secondary value at the trailing edge. */
  value?: ReactNode;
  /** Numbers are tabular so a ticking value does not shuffle the row. */
  numericValue?: boolean;
  detail?: ReactNode;
  chevron?: boolean;
  /** Leaves the app. Drawn with the outward arrow, not the push chevron. */
  external?: boolean;
  checked?: boolean;
  /** Draw the hairline below this row. The last row of a group omits it. */
  separator?: boolean;
  onClick?: () => void;
  ariaLabel?: string;
}

export function IosRow({
  icon: IconComponent,
  label,
  value,
  numericValue = false,
  detail,
  chevron = false,
  external = false,
  checked = false,
  separator = false,
  onClick,
  ariaLabel,
}: RowProps) {
  const hasValue = value !== undefined && value !== null;
  const content = (
    <>
      {IconComponent && (
        <IconComponent className="h-[19px] w-[19px] flex-none text-[var(--ios-label-2)]" />
      )}
      {/* The label keeps its natural width and the value takes what is left,
          ellipsising there — the way iOS Settings does it. A truncated label
          leaves the row meaningless; a truncated value still reads as "more". */}
      <span
        className={`min-w-0 truncate ${hasValue ? "shrink" : "flex-1"}`}
      >
        {label}
      </span>
      {hasValue && (
        <span
          className="ios-row-value min-w-0 flex-1 truncate text-end"
          dir={numericValue ? "ltr" : undefined}
        >
          {value}
        </span>
      )}
      {detail}
      {checked && (
        <Check className="h-[19px] w-[19px] flex-none text-[var(--ios-accent)]" />
      )}
      {external ? (
        <ArrowUpRight className="ios-chevron h-[15px] w-[15px]" />
      ) : (
        chevron && <ChevronRight className="ios-chevron h-[15px] w-[15px] rtl:rotate-180" />
      )}
    </>
  );

  const className = `ios-row${separator ? " ios-row-sep" : ""}${
    IconComponent ? "" : " ios-row-flush"
  }`;

  if (!onClick) return <div className={className}>{content}</div>;

  return (
    <button
      type="button"
      className={className}
      onClick={onClick}
      aria-label={ariaLabel}
    >
      {content}
    </button>
  );
}

export function IosSwitch({
  checked,
  onChange,
  label,
}: {
  checked: boolean;
  onChange: (next: boolean) => void;
  label: string;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      className="ios-switch"
      onClick={() => onChange(!checked)}
    >
      <span />
    </button>
  );
}

export function IosSwitchRow({
  icon,
  label,
  checked,
  onChange,
  separator = false,
}: {
  icon?: Icon;
  label: string;
  checked: boolean;
  onChange: (next: boolean) => void;
  separator?: boolean;
}) {
  return (
    <IosRow
      icon={icon}
      label={label}
      separator={separator}
      detail={<IosSwitch checked={checked} onChange={onChange} label={label} />}
    />
  );
}

export function IosSegmented<T extends string>({
  options,
  value,
  onChange,
  label,
  className = "",
}: {
  options: { value: T; label: string }[];
  value: T;
  onChange: (next: T) => void;
  label: string;
  className?: string;
}) {
  return (
    <div
      className={`ios-segmented ${className}`}
      role="tablist"
      aria-label={label}
      style={{ gridTemplateColumns: `repeat(${options.length}, 1fr)` }}
    >
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          role="tab"
          aria-selected={option.value === value}
          className="ios-segment"
          onClick={() => onChange(option.value)}
        >
          {option.label}
        </button>
      ))}
    </div>
  );
}

export function IosButton({
  children,
  onClick,
  filled = false,
  icon: IconComponent,
  disabled = false,
  className = "",
  ariaLabel,
}: {
  children?: ReactNode;
  onClick?: () => void;
  filled?: boolean;
  icon?: Icon;
  disabled?: boolean;
  className?: string;
  ariaLabel?: string;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      aria-label={ariaLabel}
      className={`ios-btn${filled ? " ios-btn-filled" : ""} ${className}`}
    >
      {IconComponent && (
        <IconComponent
          className={filled ? "h-[17px] w-[17px]" : "h-[17px] w-[17px]"}
        />
      )}
      {children}
    </button>
  );
}

/**
 * A pushed screen. It enters from the trailing edge so the leading edge stays
 * free for the system back gesture — the resolution of the gesture conflict in
 * docs/PLAN-MOBILE.md §3.
 */
export function IosSubpage({
  title,
  backLabel,
  onBack,
  children,
  footer,
}: {
  title: ReactNode;
  backLabel: string;
  onBack: () => void;
  children: ReactNode;
  footer?: ReactNode;
}) {
  return (
    <div className="ios-subpage" role="group" aria-label={backLabel}>
      <div className="flex h-11 items-center px-4 pt-[calc(env(safe-area-inset-top)+6px)]">
        <button
          type="button"
          onClick={onBack}
          className="-ms-1 inline-flex items-center gap-0.5 text-[17px] text-[var(--ios-title)]"
        >
          <ChevronLeft className="h-[19px] w-[19px] rtl:rotate-180" />
          {backLabel}
        </button>
      </div>
      <h1 className="px-5 pb-1 pt-1.5 text-[34px] font-bold leading-tight tracking-[-0.025em] text-[var(--ios-title)]">
        {title}
      </h1>
      <div className="ios-scroll pb-4 pt-4">{children}</div>
      {footer}
    </div>
  );
}

/** A checkmark list on its own pushed screen — the iOS way to pick one value. */
export function IosChoiceSubpage<T extends string | number>({
  title,
  backLabel,
  onBack,
  options,
  value,
  onSelect,
  note,
}: {
  title: string;
  backLabel: string;
  onBack: () => void;
  options: { value: T; label: string }[];
  value: T;
  onSelect: (next: T) => void;
  note?: string;
}) {
  return (
    <IosSubpage title={title} backLabel={backLabel} onBack={onBack}>
      <IosGroup note={note}>
        {options.map((option, index) => (
          <IosRow
            key={String(option.value)}
            label={option.label}
            checked={option.value === value}
            separator={index < options.length - 1}
            onClick={() => {
              onSelect(option.value);
              onBack();
            }}
          />
        ))}
      </IosGroup>
    </IosSubpage>
  );
}

export function IosSheet({
  onClose,
  label,
  children,
}: {
  onClose: () => void;
  label: string;
  children: ReactNode;
}) {
  return (
    <>
      <button
        type="button"
        aria-label={label}
        className="ios-scrim"
        onClick={onClose}
      />
      <div className="ios-sheet pb-[max(20px,env(safe-area-inset-bottom))] pt-2">
        <div className="mx-auto mb-3 h-[5px] w-[38px] rounded-full bg-[var(--ios-label-3)]" />
        {children}
      </div>
    </>
  );
}

/**
 * The progress instrument: track, fill, and the percent bubble above the head.
 *
 * `paused` freezes the fill and sweeps the track instead, so a lunch break can
 * never be misread as progress.
 */
export function IosProgress({
  percent,
  tone = "neutral",
  paused = false,
  showBubble = true,
  height = 8,
  className = "",
}: {
  percent: number;
  tone?: "neutral" | "overtime";
  paused?: boolean;
  showBubble?: boolean;
  height?: number;
  className?: string;
}) {
  const clamped = Math.max(0, Math.min(100, percent));
  const fill =
    tone === "overtime" ? "var(--ios-accent)" : "var(--ios-title)";

  return (
    <div className={`relative ${className}`}>
      {showBubble && !paused && (
        <div
          className="absolute bottom-[14px] -translate-x-1/2 rtl:translate-x-1/2"
          style={{ insetInlineStart: `${clamped}%` }}
        >
          <div
            dir="ltr"
            className="rounded-md px-[9px] py-[3px] text-[13px] font-semibold tabular-nums"
            style={{
              background: fill,
              color: tone === "overtime" ? "#fff" : "var(--ios-bg)",
            }}
          >
            {clamped.toFixed(1)}%
          </div>
          <div
            className="absolute left-1/2 top-full h-0 w-0 -translate-x-1/2"
            style={{
              borderLeft: "6px solid transparent",
              borderRight: "6px solid transparent",
              borderTop: `6px solid ${fill}`,
            }}
          />
        </div>
      )}
      <div
        role="progressbar"
        aria-valuenow={Math.round(clamped)}
        aria-valuemin={0}
        aria-valuemax={100}
        className={`overflow-hidden rounded-full ${
          paused ? "ios-track-paused" : "bg-[var(--ios-fill-track)]"
        }`}
        style={{ height }}
      >
        <div
          className="h-full transition-[width] duration-500 ease-linear"
          style={{
            width: `${clamped}%`,
            background: paused ? "var(--ios-label-2)" : fill,
          }}
        />
      </div>
    </div>
  );
}

/** Section label above a group, matching the iOS grouped-list header. */
export function IosSectionTitle({ children }: { children: ReactNode }) {
  return <div className="ios-group-title">{children}</div>;
}
