# frozen_string_literal: true

module UiHelper
  BADGE_TONES = {
    neutral: "bg-ink-100 text-ink-700 ring-ink-200",
    brand: "bg-brand-50 text-brand-800 ring-brand-200",
    success: "bg-emerald-50 text-emerald-800 ring-emerald-200",
    warning: "bg-amber-50 text-amber-800 ring-amber-200",
    danger: "bg-rose-50 text-rose-800 ring-rose-200",
    info: "bg-sky-50 text-sky-800 ring-sky-200",
    indigo: "bg-indigo-50 text-indigo-800 ring-indigo-200",
    ember: "bg-ember-50 text-ember-600 ring-ember-100"
  }.freeze

  AVATAR_CLASSES = "shrink-0 place-items-center rounded-full bg-ink-100 font-bold text-ink-700 ring-1 ring-inset ring-ink-200"

  DOT_TONES = {
    neutral: "bg-ink-400", brand: "bg-brand-500", success: "bg-emerald-500", warning: "bg-amber-500",
    danger: "bg-rose-500", info: "bg-sky-500", indigo: "bg-indigo-500", ember: "bg-ember-500"
  }.freeze

  def badge(text, tone: :neutral, dot: true)
    tag.span(class: "sv-badge #{BADGE_TONES.fetch(tone)}") do
      safe_join([(tag.span(class: "size-1.5 rounded-full #{DOT_TONES.fetch(tone)}", aria: { hidden: true }) if dot),
                 text].compact)
    end
  end

  def page_header(title, subtitle: nil, eyebrow: nil, &actions)
    tag.header(class: "mb-6 flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between") do
      heading = tag.div do
        safe_join([
          (tag.p(eyebrow, class: "mb-1 text-xs font-semibold uppercase tracking-widest text-brand-700") if eyebrow),
          tag.h1(title, class: "text-2xl font-bold tracking-tight text-ink-950"),
          (tag.p(subtitle, class: "mt-1 text-sm text-ink-600") if subtitle)
        ].compact)
      end
      safe_join([heading, (tag.div(class: "flex flex-wrap items-center gap-2 sm:shrink-0", &actions) if actions)].compact)
    end
  end

  def empty_state(title, description: nil, icon_name: :info, &action)
    tag.div(class: "flex flex-col items-center justify-center px-6 py-14 text-center") do
      safe_join([
        tag.div(icon(icon_name, size: 26, css: "text-brand-600"),
          class: "mb-4 grid size-12 place-items-center rounded-2xl bg-brand-50"),
        tag.p(title, class: "text-base font-semibold text-ink-900"),
        (tag.p(description, class: "mt-1 max-w-md text-sm text-ink-600") if description),
        (tag.div(class: "mt-5", &action) if action)
      ].compact)
    end
  end

  # A danger tile is marked by an alert icon and a rose tint, not by the colour of
  # the number alone (rose and the ruby brand are close hues).
  def stat_tile(label, value, hint: nil, tone: :neutral)
    danger = tone == :danger
    tag.div(class: danger ? "sv-card p-5 bg-rose-50/40 ring-1 ring-rose-200" : "sv-card p-5") do
      safe_join([
        tag.p(class: "flex items-center gap-1.5 text-xs font-semibold uppercase tracking-wide text-ink-500") do
          safe_join([(icon(:alert, size: 14, css: "text-rose-600", label: "Atenção") if danger), label].compact)
        end,
        tag.p(value, class: "sv-num mt-2 text-3xl font-bold tracking-tight #{danger ? "text-rose-700" : "text-ink-950"}"),
        (tag.p(hint, class: "mt-1 text-xs text-ink-500") if hint)
      ].compact)
    end
  end

  def avatar(name, size: :md)
    initials = name.to_s.split.first(2).pluck(0).join.upcase.presence || "?"
    dimension = size == :sm ? "size-7 text-[11px]" : "size-9 text-xs"
    tag.span(initials, class: "grid #{dimension} #{AVATAR_CLASSES}", aria: { hidden: true })
  end

  def nav_link(label, path, icon_name:, active: false)
    css = if active
            "bg-white/10 text-white"
          else
            "text-ink-300 hover:bg-white/5 hover:text-white"
          end
    link_to(path, class: "group flex items-center gap-3 rounded-xl px-3 py-2 text-sm font-medium transition #{css}",
      aria: { current: (active ? "page" : nil) }) do
      safe_join([icon(icon_name, size: 18, css: active ? "text-brand-300" : "text-ink-400 group-hover:text-brand-300"), label])
    end
  end

  def format_document(value)
    Documents::BrazilianDocument.format(value)
  end
end
