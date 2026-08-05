require "optparse"

module SnsMultipost
  module Cli
    module_function

    def parser(banner:, description:, examples: [], notes: [])
      OptionParser.new do |opts|
        opts.banner = banner
        description.lines(chomp: true).each do |line|
          opts.separator "  #{line}"
        end
        opts.separator "Options:"
        yield opts if block_given?
        opts.on("-h", "--help", "このヘルプを表示") do
          puts opts
          exit 0
        end
        unless examples.empty?
          opts.separator "Examples:"
          examples.each { |example| opts.separator "  #{example}" }
        end
        unless notes.empty?
          opts.separator "Notes:"
          notes.each { |note| opts.separator "  #{note}" }
        end
      end
    end

    def parse!(parser, argv = ARGV)
      parser.parse!(argv)
    rescue OptionParser::ParseError => e
      usage_error(parser, e.message)
    end

    def reject_arguments!(parser, argv = ARGV)
      return if argv.empty?
      usage_error(parser, "余分な引数があります: #{argv.join(' ')}")
    end

    def usage_error(parser, message)
      warn message
      warn
      warn parser
      exit 2
    end
  end
end
