require "conceptql"
require "json"
require "open3"
require "tmpdir"

# Draws a ConceptQL statement as the Jigsaw Diagram Editor draws it.
#
# conceptql builds a `conceptql-diagram/v1` render tree for the statement --
# annotated with per-edge row/person counts from the claims database -- and the
# editor's standalone `conceptql-diagram` CLI turns that tree into a
# self-contained SVG (fonts and icons embedded, animation off).
#
# The CLI lives in the Jigsaw Diagram Editor's checkout, so it is located only
# through the CONCEPTQL_DIAGRAM_CLI environment variable (see the contributor
# notes at the end of README.cql.md).
class DiagramRenderer
  class Error < StandardError; end

  CLI_ENV = "CONCEPTQL_DIAGRAM_CLI".freeze
  CLI_FLAGS = %w[--show-counts --show-options].freeze

  attr_reader :cdb

  def initialize(cdb)
    @cdb = cdb
    cli # fail before any work if the renderer cannot be found
  end

  # Returns the SVG for +statement+ as a string.
  def svg(statement)
    render(tree(statement))
  end

  # The render tree, with counts. A statement conceptql cannot count (an
  # experimental operator, or one this test database cannot run) is still
  # drawn, just without counts -- as the GraphViz grapher did before it.
  def tree(statement)
    ConceptQL::Diagram.render([statement], cdb: cdb, counts: true)
  rescue StandardError => e
    warn "diagram: no counts for #{statement.to_json}: #{e.class}: #{e.message}"
    ConceptQL::Diagram.render([statement], cdb: cdb, counts: false)
  end

  private

  def render(tree)
    Dir.mktmpdir("conceptql-diagram") do |dir|
      out = File.join(dir, "diagram.svg")
      _stdout, stderr, status = Open3.capture3("node", cli, "render", "-", "-o", out, *CLI_FLAGS,
                                               stdin_data: JSON.generate(tree))
      raise Error, "conceptql-diagram failed (#{status}):\n#{stderr}" unless status.success?

      File.read(out)
    end
  end

  def cli
    @cli ||= begin
      path = ENV[CLI_ENV].to_s
      raise Error, <<~MSG if path.empty?
        #{CLI_ENV} is not set. Point it at the Jigsaw Diagram Editor's renderer CLI,
        frontend/lib/conceptql-diagram/cli/bin/conceptql-diagram.js in a checkout of
        jigsaw-diagram-editor whose CLI dependencies are installed (npm ci in its cli/).
      MSG
      raise Error, "#{CLI_ENV}=#{path} does not exist" unless File.file?(path)

      path
    end
  end
end
