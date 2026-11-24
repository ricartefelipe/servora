# frozen_string_literal: true

# Plain file checks (no Rails boot) that keep the "Precisão" colour grammar:
# ruby fills or marks, rose warns. Each rule lists the legitimate exceptions
# from the design specification; every failure names the file and the line.
RSpec.describe "Design guardrails" do # rubocop:disable RSpec/DescribeClass -- checks source files, not a class
  def root = File.expand_path("../..", __dir__)
  def files(*patterns) = patterns.flat_map { |pattern| Dir.glob(File.join(root, pattern)) }.sort
  def relative(path) = path.delete_prefix("#{root}/")
  def view_files = files("app/views/**/*.erb")
  def helper_files = files("app/helpers/**/*.rb")
  def stylesheet_files = files("app/assets/tailwind/**/*.css")

  # "path:line: excerpt" for every match of pattern in the given files.
  def offences(paths, pattern, except: [])
    paths.reject { |path| except.any? { |allowed| File.fnmatch?(allowed, relative(path), File::FNM_PATHNAME) } }
      .flat_map do |path|
        File.read(path).each_line.with_index(1).filter_map do |line, number|
          "#{relative(path)}:#{number}: #{line.strip[0, 160]}" if line.match?(pattern)
        end
      end
  end

  # Like offences, but for multi-line fragments (ERB tags, HTML tags, Ruby calls).
  def fragment_offences(path, fragments, pattern)
    source = File.read(path)
    fragments.filter_map do |fragment, offset|
      next unless fragment.match?(pattern)

      "#{relative(path)}:#{source[0, offset].count("\n") + 1}: #{fragment.squeeze(" ").strip[0, 160]}"
    end
  end

  def scan_with_offsets(source, regexp)
    source.to_enum(:scan, regexp).map { [Regexp.last_match[0], Regexp.last_match.begin(0)] }
  end

  # Text inside balanced parentheses starting at the "(" found at index.
  def balanced_call(source, index)
    depth = 0
    source[index..].each_char.with_index do |char, step|
      depth += 1 if char == "("
      depth -= 1 if char == ")"
      return source[index, step + 1] if depth.zero?
    end
    source[index..]
  end

  # Icons inside a link may carry the ruby mark (active navigation), so icon(...) calls are left out.
  def without_icons(code)
    while (index = code =~ /\bicon\(/)
      start = code.index("(", index)
      code = code[0, index] + code[(start + balanced_call(code, start).size)..].to_s
    end
    code
  end

  def constant_block(source, name)
    source[/^\s*#{name}\s*=\s*\{.*?\}\.freeze/m]
  end

  it "has source files to check" do
    expect([view_files, helper_files, stylesheet_files].map(&:size)).to all(be_positive)
  end

  it "never paints danger as a solid rose or red fill" do
    # Tints (bg-rose-600/10) are fine; only opaque 600/700 fills are refused.
    pattern = %r{\bbg-(?:rose|red)-(?:600|700)\b(?!/)}

    expect(offences(view_files + helper_files + stylesheet_files, pattern)).to be_empty
  end

  it "keeps ruby out of status badges" do
    helper = File.read(File.join(root, "app/helpers/ui_helper.rb"))
    blocks = { "BADGE_TONES" => constant_block(helper, "BADGE_TONES"), "DOT_TONES" => constant_block(helper, "DOT_TONES") }
    badge_method = helper[/^\s*def badge\b.*?^\s{2}end$/m]

    expect(blocks.values + [badge_method]).to all(be_a(String))
    expect(blocks.merge("badge" => badge_method).select { |_name, code| code.include?("brand-") }.keys).to be_empty

    status_tones = files("app/**/*.rb").filter_map { |path| [path, constant_block(File.read(path), "STATUS_TONES")] }
      .select { |_path, code| code&.include?("brand-") }
    expect(status_tones.map { |path, _code| relative(path) }).to be_empty
    expect(offences(files("app/views/**/_status_badge*.erb"), /\bbrand-/)).to be_empty
  end

  it "keeps blur blobs out of the product (login panel and gem art excepted)" do
    allowed = ["app/views/layouts/account.html.erb", "app/views/shared/_gem*.erb"]

    expect(offences(view_files, /\bblur-3xl\b/, except: allowed)).to be_empty
  end

  it "never uses red or coloured shadows" do
    red_shadow = /rgba?\(\s*200[\s,_]+16[\s,_]+46\b/
    coloured_shadow = /\bshadow-(?:brand|rose|red)-\d/

    expect(offences(view_files + helper_files + stylesheet_files, red_shadow)).to be_empty
    expect(offences(view_files + helper_files, coloured_shadow)).to be_empty
  end

  it "never writes link text in ruby" do
    ruby_text = /\btext-brand-(?:500|600|700)\b/
    view_links = view_files.flat_map do |path|
      source = File.read(path)
      erb_links = scan_with_offsets(source, /<%=?.*?%>/m).select { |tag, _| tag.match?(/\blink_to\b/) }
      anchors = scan_with_offsets(source, /<a\b[^>]*>/m)
      fragment_offences(path, (erb_links + anchors).map { |code, offset| [without_icons(code), offset] }, ruby_text)
    end
    helper_links = helper_files.flat_map do |path|
      source = File.read(path)
      calls = source.enum_for(:scan, /\blink_to\s*\(/).map do
        start = Regexp.last_match.end(0) - 1
        [without_icons(balanced_call(source, start)), start]
      end
      link_constants = scan_with_offsets(source, /^\s*[A-Z_]*LINK[A-Z_]*\s*=\s*(?:"[^"]*"\s*\\?\s*)+/)
      fragment_offences(path, calls + link_constants, ruby_text)
    end

    expect(view_links + helper_links).to be_empty
  end

  it "keeps the flat brand-700 hero to the dashboard cover and the field's next visit" do
    # Variants (hover:bg-brand-700) and tints (bg-brand-700/40) are not the hero block.
    hero = %r{(?<![\w:/-])bg-brand-700(?=["'\s])}
    allowed = ["app/views/dashboards/show.html.erb", "app/views/field/**/*.erb"]

    expect(offences(view_files + helper_files, hero, except: allowed)).to be_empty
  end

  it "reserves the cover page header to the dashboard" do
    expect(offences(view_files + helper_files, /variant:\s*:cover\b/, except: ["app/views/dashboards/show.html.erb"]))
      .to be_empty
  end
end
