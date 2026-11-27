# frozen_string_literal: true

# Servora icon set: 24x24 outline glyphs drawn for the product. Paths are
# constants, never user input.
module IconsHelper
  ICONS = {
    dashboard: ["M4 13h6V4H4z", "M14 20h6v-9h-6z", "M14 8h6V4h-6z", "M4 20h6v-3H4z"],
    orders: ["M9 4h6", "M8 6H6.5A1.5 1.5 0 0 0 5 7.5v12A1.5 1.5 0 0 0 6.5 21h11a1.5 1.5 0 0 0 1.5-1.5v-12A1.5 1.5 0 0 0 17.5 6H16",
             "M9 3h6v3H9z", "M8.5 12.5l2 2 4-4", "M8.5 17h7"],
    calendar: ["M5 6h14a1 1 0 0 1 1 1v12a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1z", "M4 10h16", "M8 3v4", "M16 3v4",
               "M8 14h3v3H8z"],
    quote: ["M7 3h7l5 5v12a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z", "M14 3v5h5", "M9 13h6", "M9 17h4"],
    customers: ["M9 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7z", "M3 20c.6-3.4 3-5.5 6-5.5s5.4 2.1 6 5.5", "M16 4.5a3.5 3.5 0 0 1 0 6.5",
                "M18 14.8c1.6.7 2.6 2.4 3 5.2"],
    equipment: ["M4 6h16v10H4z", "M8 20h8", "M12 16v4", "M8 10h3", "M14.5 9.5l1.5 1.5 1.5-1.5"],
    preventive: ["M20 11a8 8 0 1 0-2.3 5.7", "M20 5v6h-6", "M12 8v4l2.5 1.5"],
    stock: ["M4 7.5L12 3l8 4.5v9L12 21l-8-4.5z", "M4 7.5l8 4.5 8-4.5", "M12 12v9"],
    catalog: ["M3.5 12.5l8-8H19a1 1 0 0 1 1 1v7.5l-8 8a1 1 0 0 1-1.4 0l-7.1-7.1a1 1 0 0 1 0-1.4z", "M15.5 8.5h.01"],
    finance: ["M4 7h16v10H4z", "M12 9.5a2.5 2.5 0 1 0 0 5 2.5 2.5 0 0 0 0-5z", "M7 10v4", "M17 10v4"],
    reports: ["M4 20V10", "M10 20V4", "M16 20v-7", "M21 20H3"],
    team: ["M12 11a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7z", "M5 20c.8-3.6 3.6-6 7-6s6.2 2.4 7 6"],
    integrations: ["M9 7V3", "M15 7V3", "M6 7h12v4a6 6 0 0 1-12 0z", "M12 17v4"],
    audit: ["M12 3l7 3v6c0 4.2-2.9 7.8-7 9-4.1-1.2-7-4.8-7-9V6z", "M9 12l2 2 4-4"],
    settings: ["M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z",
               "M19 12a7 7 0 0 0-.1-1.2l2-1.5-2-3.4-2.3.9a7 7 0 0 0-2-1.2L14.2 3h-4.4l-.4 2.6a7 7 0 0 0-2 1.2l-2.3-.9-2 3.4 2 1.5a7 7 0 0 0 0 2.4l-2 1.5 2 3.4 2.3-.9a7 7 0 0 0 2 1.2l.4 2.6h4.4l.4-2.6a7 7 0 0 0 2-1.2l2.3.9 2-3.4-2-1.5c.1-.4.1-.8.1-1.2z"],
    bell: ["M6 16V11a6 6 0 1 1 12 0v5l1.5 2h-15z", "M10 20a2 2 0 0 0 4 0"],
    logout: ["M15 4h3a1 1 0 0 1 1 1v14a1 1 0 0 1-1 1h-3", "M10 16l-4-4 4-4", "M6 12h10"],
    menu: ["M4 7h16", "M4 12h16", "M4 17h16"],
    close: ["M6 6l12 12", "M18 6L6 18"],
    chevron_right: ["M9 6l6 6-6 6"],
    chevron_down: ["M6 9l6 6 6-6"],
    dots_horizontal: ["M5.5 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2z", "M12 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2z",
                      "M18.5 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2z"],
    plus: ["M12 5v14", "M5 12h14"],
    search: ["M11 18a7 7 0 1 0 0-14 7 7 0 0 0 0 14z", "M20 20l-4-4"],
    check: ["M5 12.5l4.5 4.5L19 7.5"],
    alert: ["M12 4l9 16H3z", "M12 10v4", "M12 17h.01"],
    info: ["M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z", "M12 11v5", "M12 8h.01"],
    clock: ["M12 21a9 9 0 1 0 0-18 9 9 0 0 0 0 18z", "M12 7v5l3 2"],
    pause: ["M9 6v12", "M15 6v12"],
    pin: ["M12 21s7-6.1 7-11.5a7 7 0 1 0-14 0C5 14.9 12 21 12 21z", "M12 12a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z"],
    phone: ["M5 4h3.5l1.5 4-2 1.5a11 11 0 0 0 6.5 6.5l1.5-2 4 1.5V19a1 1 0 0 1-1 1A16 16 0 0 1 4 5a1 1 0 0 1 1-1z"],
    mail: ["M4 6h16v12H4z", "M4 7l8 6 8-6"],
    key: ["M14.5 13a4.5 4.5 0 1 0-4-2.5L4 17v3h3v-2h2v-2h2l1.5-1.5"],
    device: ["M8 3h8a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H8a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1z", "M11 18h2"],
    monitor: ["M4 5h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z", "M9 21h6", "M12 17v4"],
    switch: ["M7 7h12l-3-3", "M17 17H5l3 3"],
    building: ["M5 21V5a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v16", "M15 10h3a1 1 0 0 1 1 1v10", "M3 21h18", "M8.5 8h3", "M8.5 12h3",
               "M8.5 16h3"],
    wrench: ["M14.5 6.5a4 4 0 0 0 5 5L12 19a2.1 2.1 0 0 1-3-3l7.5-7.5a4 4 0 0 0-2-2z"],
    camera: ["M4 8h3l1.5-2h7L17 8h3v11H4z", "M12 16.5a3 3 0 1 0 0-6 3 3 0 0 0 0 6z"],
    download: ["M12 4v11", "M7.5 10.5L12 15l4.5-4.5", "M5 20h14"],
    eye: ["M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z", "M12 14.5a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z"],
    trash: ["M5 7h14", "M10 11v6", "M14 11v6", "M6 7l1 13h10l1-13", "M9 7V4h6v3"]
  }.freeze

  def icon(name, size: 20, css: nil, label: nil)
    paths = ICONS.fetch(name.to_sym)
    accessibility = label ? { role: "img", aria: { label: } } : { aria: { hidden: true }, focusable: "false" }
    tag.svg(width: size, height: size, viewBox: "0 0 24 24", fill: "none", stroke: "currentColor",
      "stroke-width": 1.75, "stroke-linecap": "round", "stroke-linejoin": "round",
      class: ["shrink-0", css].compact.join(" "), **accessibility) do
      safe_join(paths.map { |d| tag.path(d:) })
    end
  end
end
