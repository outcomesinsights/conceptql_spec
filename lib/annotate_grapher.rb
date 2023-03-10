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
    link_to(g, statement, root, blank)

    g.output(output_type => file_path)
  end

  private

  DOMAIN_COLORS = {
    person: 'blue',
    visit_occurrence: 'orange',
    condition_occurrence: 'red',
    procedure_occurrence: 'green3',
    procedure_cost: 'gold',
    death: 'brown',
    payer_plan_period: 'blue',
    drug_exposure: 'purple',
    observation: 'magenta',
    misc: 'black',
    invalid: 'gray'
  }

  def domain_color(*domains)
    domains.flatten!
    domains.length == 1 ? DOMAIN_COLORS[domains.first] || 'gray' : 'black'
  end

  def domains(op)
    domains = op.last[:annotation][:counts].keys
    return [:invalid] if domains.length == 0
    domains
  end

  def link_to(g, from, from_node, to)
    edge_options = {}

    opts = from.last[:annotation]
    domains(from).each do |domain|
      domain_opts = opts[:counts][domain] || {}
      #next unless (domain_opts = (opts[:counts][domain])).is_a?(Hash)
      n = domain_opts[:n]
      if n
        edge_options[:label] = " rows=#{commatize(opts[:counts][domain][:rows])} \n n=#{commatize(n)}"
        edge_options[:style] = 'dashed' if n.zero?
      end
      e = g.add_edges(from_node, to, edge_options)
      e[:color] = domain_color(domain)
    end
  end

  def traverse(g, op)
    op_name, *args, opts = op
    node_name = "#{op_name}_#{@counter += 1}"
    upstreams, args = args.partition { |arg| arg.is_a?(Array) }
    upstreams.map! do |upstream|
      [upstream, traverse(g, upstream)]
    end

    if left = opts[:left]
      right = opts[:right]
      left_node = traverse(g, left)
      right_node = traverse(g, right)
    else
      me = g.add_nodes(node_name)
      me[:color] = domain_color(*domains(op))
    end
    label = opts[:name] || op_name.to_s.titlecase
    unless args.empty?
      label += ":\n"
      args_str = args.join(', ')
      if args_str.length <= 100
        label += args_str
      else
        parts = args_str.split
        label += parts.each_slice(args_str.length / parts.count).map do |subparts|
          subparts.join(' ')
        end.join ('\n')
      end
    end
    exclude = [:annotation, :name, :left, :right]
    label_opts = opts.reject{|k,_| exclude.include?(k)}
    label += "\n#{label_opts.map{|k,v| "#{k}: #{v}"}.join("\n")}" unless label_opts.nil? || label_opts.empty?

    upstreams.each do |upstream, node|
      link_to(g, upstream, node, me)
    end

    if left_node
      cluster_name = "cluster_#{op_name}_#{@counter += 1}"
      me = g.send(cluster_name) do |sub|
        sub[rank: 'same', label: label, color: 'black']
        sub.send("#{cluster_name}_left").send('[]', shape: 'point', color: domain_color(*domains(op)))
        sub.send("#{cluster_name}_right").send('[]', shape: 'point')
      end
      link_to(g, left, left_node, me.send("#{cluster_name}_left"))
      link_to(g, right, right_node, me.send("#{cluster_name}_right"))
      me = me.send("#{cluster_name}_left")
    end

    me[:label] = label
    me
  end

  def commatize(number)
    number.to_s.chars.reverse.each_slice(3).map(&:join).join(',').reverse
  end
end