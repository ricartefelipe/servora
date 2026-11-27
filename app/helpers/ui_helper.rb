# frozen_string_literal: true

module UiHelper
  # Status tones. Ruby is never a status colour, so there is no brand tone.
  BADGE_TONES = {
    neutral: "bg-ink-50 text-ink-700 ring-ink-950/10",
    success: "bg-emerald-50 text-emerald-800 ring-emerald-600/20",
    warning: "bg-amber-50 text-amber-800 ring-amber-600/20",
    danger: "bg-rose-50 text-rose-800 ring-rose-600/20",
    info: "bg-sky-50 text-sky-800 ring-sky-600/20",
    indigo: "bg-indigo-50 text-indigo-800 ring-indigo-600/20",
    ember: "bg-ember-50 text-ember-600 ring-ember-500/25"
  }.freeze

  DOT_TONES = {
    neutral: "bg-ink-400", success: "bg-emerald-500", warning: "bg-amber-500",
    danger: "bg-rose-500", info: "bg-sky-500", indigo: "bg-indigo-500", ember: "bg-ember-500"
  }.freeze

  # Colour of a glyph that replaces the dot (badge marker:, chart legends).
  MARKER_TONES = {
    neutral: "text-ink-500", success: "text-emerald-600", warning: "text-amber-600",
    danger: "text-rose-600", info: "text-sky-600", indigo: "text-indigo-600", ember: "text-ember-600"
  }.freeze

  AVATAR_CLASSES = "shrink-0 place-items-center rounded-full bg-white font-semibold text-ink-800 ring-1 ring-inset ring-ink-200"

  # Danger badges swap the dot for an alert icon, so the state never depends on
  # colour alone.
  # marker: an icon name drawn instead of the dot, in the tone colour.
  def badge(text, tone: :neutral, dot: true, marker: nil)
    glyph = if tone == :danger
              icon(:alert, size: 12, css: "text-rose-600")
            elsif marker
              icon(marker, size: 12, css: MARKER_TONES.fetch(tone))
            elsif dot
              tag.span(class: "size-1.5 rounded-full #{DOT_TONES.fetch(tone)}", aria: { hidden: true })
            end
    tag.span(class: "sv-badge #{BADGE_TONES.fetch(tone)}") { safe_join([glyph, text].compact) }
  end

  PAGE_TITLE_SIZES = { lg: "text-display-lg", md: "text-display-md" }.freeze

  # Page heading: an optional eyebrow led by the ruby facet, a display title,
  # an optional meta row (status badges stay here, away from the actions), a
  # subtitle and up to a few actions (one primary at most).
  def page_header(title, subtitle: nil, eyebrow: nil, size: :lg, meta: nil, &actions)
    tag.header(class: "mb-6 flex flex-col gap-4 pt-1 sm:flex-row sm:items-end sm:justify-between") do
      heading = tag.div(class: "min-w-0") do
        safe_join([
          (if eyebrow
             tag.p(class: "sv-eyebrow mb-2") do
               safe_join([tag.span(class: "sv-facet", aria: { hidden: true }), eyebrow])
             end
           end),
          tag.h1(title, class: "sv-display #{PAGE_TITLE_SIZES.fetch(size)} text-ink-950"),
          (tag.div(meta, class: "mt-2 flex flex-wrap items-center gap-2") if meta),
          (tag.p(subtitle, class: "mt-1.5 max-w-prose text-sm text-ink-600") if subtitle)
        ].compact)
      end
      safe_join([heading, (tag.div(class: "flex flex-wrap items-center gap-2 sm:shrink-0", &actions) if actions)].compact)
    end
  end

  def empty_state(title, description: nil, icon_name: :info, &action)
    tag.div(class: "flex flex-col items-center justify-center px-6 py-16 text-center") do
      safe_join([
        tag.div(class: "relative mb-5 grid size-14 place-items-center rounded-2xl bg-white ring-1 ring-ink-200") do
          safe_join([icon(icon_name, size: 24, css: "text-ink-600"),
                     tag.span(class: "sv-facet absolute -right-0.5 -top-0.5 size-2", aria: { hidden: true })])
        end,
        tag.p(title, class: "text-[15px] font-semibold text-ink-950"),
        (tag.p(description, class: "mt-1 max-w-md text-[13px] text-ink-600") if description),
        (tag.div(class: "mt-5", &action) if action)
      ].compact)
    end
  end

  # A danger tile is marked by an alert icon and a rose tint, not by the colour
  # of the number alone.
  def stat_tile(label, value, hint: nil, tone: :neutral)
    danger = tone == :danger
    tag.div(class: danger ? "sv-card p-5 bg-rose-50/50 ring-rose-200" : "sv-card p-5") do
      safe_join([
        tag.p(class: "flex items-center gap-1.5 text-xs font-medium text-ink-600") do
          safe_join([(icon(:alert, size: 14, css: "text-rose-600", label: "Atenção") if danger), label].compact)
        end,
        tag.p(value, class: "sv-num mt-2 text-[28px] font-semibold leading-none tracking-tight text-ink-950"),
        (tag.p(hint, class: "mt-2 text-xs text-ink-500") if hint)
      ].compact)
    end
  end

  def avatar(name, size: :md)
    initials = name.to_s.split.first(2).pluck(0).join.upcase.presence || "?"
    dimension = size == :sm ? "size-7 text-[11px]" : "size-8 text-xs"
    tag.span(initials, class: "grid #{dimension} #{AVATAR_CLASSES}", aria: { hidden: true })
  end

  NAV_LINK_BASE = "group relative flex h-8 items-center gap-2.5 rounded-md px-2 text-[13px] transition-colors duration-150"
  NAV_LINK_ACTIVE = "bg-white font-semibold text-ink-950 shadow-[var(--shadow-xs)] ring-1 ring-ink-950/[0.06] " \
                    "forced-colors:bg-[Highlight] forced-colors:text-[HighlightText]"
  NAV_LINK_IDLE = "font-medium text-ink-700 hover:bg-ink-950/[0.04] hover:text-ink-950"

  # Sidebar entry. The active one is a white pill with the ruby marker on the
  # sidebar edge, a heavier weight and aria-current, so colour is not the only cue.
  def nav_link(label, path, icon_name:, active: false)
    link_to(path, class: "#{NAV_LINK_BASE} #{active ? NAV_LINK_ACTIVE : NAV_LINK_IDLE}",
      aria: { current: (active ? "page" : nil) }) do
      safe_join([
        (if active
           tag.span(class: "absolute -left-3 top-1/2 h-5 w-[3px] -translate-y-1/2 rounded-r-full bg-brand-600",
             aria: { hidden: true })
         end),
        icon(icon_name, size: 16, css: active ? "text-brand-600" : "text-ink-500 group-hover:text-ink-700"),
        tag.span(label, class: "truncate")
      ].compact)
    end
  end

  def format_document(value)
    Documents::BrazilianDocument.format(value)
  end
end
