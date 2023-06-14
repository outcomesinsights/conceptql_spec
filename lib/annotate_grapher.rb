require "facets/string/titlecase"
require "graphviz"

class AnnotateGrapher
  def graph_it(statement, file_path, opts={})
    raise "statement not annotated" unless statement.last[:annotation]
    @counter = 0

    output_type = opts.delete(:output_type) || File.extname(file_path).sub('.', '')

    opts  = opts.merge( type: :digraph )
    g = GraphViz.new(:G, opts)
    root = traverse(g, statement)

    blank = g.add_nodes("_blank")
    blank[:shape] = 'none'
    blank[:height] = 0
    blank[:label] = ''
    blank[:fixedsize] = true
    link_to(g, statement, root, blank, tailport: "MIDDLE")

    g.output(output_type => file_path)
  end

  private

  DOMAIN_COLORS = {
    person: "#7193cd",
    visit_occurrence: "#d1a776",
    condition_occurrence: "#ad4a5b",
    procedure_occurrence: "#90d796",
    procedure_cost: 'gold',
    death: "#704a4a",
    payer_plan_period: 'blue',
    drug_exposure: "#9f57a5",
    observation: "#6fbbba",
    misc: "#959294",
    invalid: 'gray'
  }

  def domain_color(*domains)
    domains.flatten!
    domains.length == 1 ? DOMAIN_COLORS[domains.first] || 'gray' : "#959294"
  end

  def domains(op)
    domains = op.last[:annotation][:counts].keys
    return [:invalid] if domains.length == 0
    domains
  end

  def link_to(g, from, from_node, to, edge_options = {})
    edge_options = {
      fontname: "Roboto,sans-serif"
    }.merge(edge_options)

    opts = from.last[:annotation]
    domains(from).each do |domain|
      domain_opts = opts[:counts][domain] || {}
      #next unless (domain_opts = (opts[:counts][domain])).is_a?(Hash)
      n = domain_opts[:n]
      if n
        edge_options[:label] = %Q{<<FONT COLOR="#817980">&nbsp;rows=#{commatize(opts[:counts][domain][:rows])}<BR />&nbsp;n=#{commatize(n)}</FONT>>}
        edge_options[:style] = 'dashed' if n.zero?
      end
      e = g.add_edges(from_node, to, edge_options)
      e[:color] = domain_color(domain)
    end
  end

  def wrap_args(args, line_length)
    args_str = args.join(', ')

    return args_str if args_str.length <= line_length

    parts = args_str.split

    line = []
    lines = []

    while next_tok = parts.shift
      line << next_tok
      if line.map(&:length).inject(&:+) >= line_length
        lines << line.join(" ")
        line = []
      end
    end
    
    lines.join('<BR />')
  end

  def construct_label(opts, args)
    args_n_opts = ""
    unless args.empty?
      args_n_opts = wrap_args(args, 30)
    end

    exclude = [:annotation, :name, :color, :left, :right]
    label_opts = opts.reject{|k,_| exclude.include?(k)}
    unless label_opts.blank?
      args_n_opts += "<BR />" unless args_n_opts.empty?
      args_n_opts += label_opts.map{|k,v| "#{k}: #{v}"}.join("<BR />")
    end

    args_n_opts = "&nbsp;" if args_n_opts.blank?
    
    label = %Q{<<TABLE BORDER="0" CELLBORDER="-1" CELLSPACING="-1">
        <TR>
          <TD WIDTH="20" ROWSPAN="2" BGCOLOR="#{opts[:color]}" PORT="LEFT"></TD>
          <TD WIDTH="20" ROWSPAN="2" BGCOLOR="#{opts[:color]}" PORT="MIDDLE"></TD>
          <TD WIDTH="20" ROWSPAN="2" BGCOLOR="#{opts[:color]}" PORT="RIGHT"></TD>
          <TD ALIGN="LEFT"><B><FONT POINT-SIZE="16">#{opts[:name]}</FONT></B></TD>
        </TR>
        <TR>
          <TD ALIGN="LEFT"><FONT COLOR="#817980">#{args_n_opts}</FONT></TD>
        </TR>
      </TABLE>>}.gsub("\n", "")
  end

  def traverse(g, op)
    op_name, *args, opts = op
    opts[:name] ||= op_name.to_s.titlecase
    opts[:color] = domain_color(*domains(op))
    node_name = "#{op_name}_#{@counter += 1}"
    upstreams, args = args.partition { |arg| arg.is_a?(Array) }
    upstreams.map! do |upstream|
      [upstream, traverse(g, upstream)]
    end

    me = g.add_nodes(node_name, label: construct_label(opts, args), shape: :plaintext, fontname: "Roboto,sans-serif")

    if left = opts[:left]
      right = opts[:right]
      right_node = traverse(g, right)
      left_node = traverse(g, left)
      link_to(g, left, left_node, me, tailport: "MIDDLE", headport: "LEFT")
      link_to(g, right, right_node, me, tailport: "MIDDLE", headport: "RIGHT")
    end

    upstreams.each do |upstream, node|
      link_to(g, upstream, node, me, tailport: "MIDDLE", headport: "MIDDLE")
    end

    me
  end

  def commatize(number)
    number.to_s.chars.reverse.each_slice(3).map(&:join).join(',').reverse
  end
end