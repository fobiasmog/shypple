# frozen_string_literal: true

require "stringio"

# Runs the CLI in process with string streams and returns what it produced.
module CliRunner
  CliRun = Data.define(:status, :stdout, :stderr)

  def run_cli(input, store:, feed: Paths::SAMPLE_FEED)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Shypple::CLI.new(feed_path: feed, store:, stdin: StringIO.new(input), stdout:, stderr:).run
    CliRun.new(status:, stdout: stdout.string, stderr: stderr.string)
  end
end

RSpec.configure { |config| config.include CliRunner }
