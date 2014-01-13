#!/usr/bin/env ruby
#
# This command line app links Sonar, Crucible and Jenkins
# Run `./sonar_blamethrower.rb help` for usage instructions

SRC_PREFIX_REGEX = %r{code/(src|test)/}

require 'rubygems'
require 'commander/import'
require 'rugged'
require 'set'
require 'net/http'
require 'net/smtp'
require 'json'
require 'rexml/document'
require 'cgi'

$stdout.sync = true

program :version, '0.0.1'
program :description, 'Match Sonar issues to authors and reviews'

command :review do |c|
  c.syntax = 'review <REVIEW_ID>'
  c.summary = 'List issues introduced in the specified Crucible review.'
  c.description = 'List issues introduced in the specified Crucible review.

The script consults Crucible to establish which commits belong to the specified
review (it will prompt you for your Crucible password), and then proceeds just
as in the `commit` case. See the remarks on `help commit` for more.

The logic to establish which commits belong to a review does not work all that
well. See the extended discussion at
https://answers.atlassian.com/questions/235556'
  c.example '1', "#{$0} review --project my:project CR-ABC-370"
  c.option '--project STRING', String, 'The Sonar project key, e.g. "my:project" (listed on the main page for the project in Sonar)'

  c.action do |args, options|
    raise 'Expecting one review id' unless args.length == 1
    raise '--project is required' unless options.project

    # https://docs.atlassian.com/fisheye-crucible/latest/wadl/crucible.html#d2e933
    # use XML as JSON parsing doesn't work that well here
    uri = URI.parse("https://jira.softwire.com/fisheye/rest-service/reviews-v1/#{args.first}/details")
    review_xml = Net::HTTP.start(uri.host,
                                  uri.port,
                                  :use_ssl => uri.scheme == 'https',
                                  :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|
      req = Net::HTTP::Get.new uri.request_uri
      req.basic_auth ENV['USERNAME'], get_password
      response = http.request req

      raise response.inspect unless response.code == "200"
      response.body
    end
    review = REXML::Document.new review_xml

    # we have to group the revisions by file, due to
    # https://answers.atlassian.com/questions/235556/crucible-get-list-of-changesets-revisions-in-a-review/238685
    revisions_by_filename = Hash.new{|h,k| h[k] = [] }

    review.elements.each(
      'detailedReviewData/reviewItems/reviewItem/expandedRevisions') do |rev|

      filename = rev.elements['path'].text
      revisions_by_filename[filename] << rev
    end

    commits = Set.new
    revisions_by_filename.each do |filename, revisions|
      if revisions.length == 1
        commits << revisions.first.elements['revision'].text
      else

        # TODO: this doesn't work https://answers.atlassian.com/questions/235556/crucible-get-list-of-changesets-revisions-in-a-review/249721
        # if 'Added' == revisions.first.elements['commitType'].text
        #  # For a file which has been added then modified in the same reivew,
        #  # all commits in the slider belong to the review.
        #  puts "WARNING: '#{filename}' is both added and modified in this review."
        #  puts "  Only the modifications will be shown by default. See [https://jira.atlassian.com/browse/CRUC-6671|CRUC-6671]"
        #else

        # Drop the first revision: it's Crucible adding the "before" rev to the slider
        revisions.shift

        hashes = revisions.map {|r| r.elements['revision'].text}
        commits += hashes
      end
    end

    puts "Warning: the logic to determine which commits are in which review is not always accurate,"
    puts "especially if the review has lots of revisions, and certainly if any intermediate revisions"
    puts "have been auto-included by Crucible."
    puts "See https://answers.atlassian.com/questions/235556/crucible-get-list-of-changesets-revisions-in-a-review"
    puts

    puts "Found commits:"
    commit_summaries_from_hashes(commits).each {|line| puts line}
    puts

    issues = []
    each_issue_for_commits(options.project, commits) { |issue| issues << issue }

    issues.sort! {|a,b| a['component'] <=> b['component'] }

    puts "Found issues:"
    issues.each do |issue|
      url = "http://sonar.zoo.lan/issue/show/" + issue['key']
      filename = issue['component'].gsub('.', '/').sub(/.*:/, '') + '.java'
      puts "#{filename}:#{issue['line']} [sonar|#{url}]: #{issue['message']}"
      puts
    end
  end
end

command :jenkins do |c|
  c.syntax = 'jenkins'
  c.summary = 'Run during a Jenkins build (after Sonar) to email authors about new issues.'
  c.description = 'Run this command during a Jenkins build, and after the Sonar plugin has run.

It will determine which changes are included in the current build, look up whether
any new Sonar issues were introduced by those changes, and email the authors with
the details.

The script consults the Jenkins environment variables and XML API to establish
which commits belong to the currently running build, and then proceeds just as in
the `commit` case. See the remarks on `help commit` for more.

You should run this command after the Sonar analysis step in your build process,
otherwise Sonar won\'t have the correct details.'
  c.example '1', "#{$0} jenkins --project my:project"
  c.option '--project STRING', String, 'The Sonar project key, e.g. "my:project" (listed on the main page for the project in Sonar)'

  c.action do |args, options|
    raise '--project is required' unless options.project

    # Look up which commits are included in this build
    commits = get_commit_list_for_current_jenkins_build

    commits_by_author = Hash.new{|h,k| h[k] = []}
    commits.each do |commit|
      commits_by_author[get_author_email(commit)] << commit
    end

    commits_by_author.each do |author, commits|
      commit_log = commit_summaries_from_hashes(commits)

      email = <<END
<html>
<body>
<h1>
  Sonar issues introduced in Jenkins build
  <a href="#{ENV['BUILD_URL']}">
    #{ENV['JOB_NAME']} #{ENV['BUILD_NUMBER']}
  </a>
</h1>
<p>You made the following commits which were included in this build:
  <ul>
    <li>#{commit_log.join("</li>\n    <li>")}</li></ul>
</p>
<p>The following issues were detected by Sonar:
  <ul>
END

      issues_found = false
      each_issue_for_commits(options.project, commits) do |issue|
        url = "http://sonar.zoo.lan/issue/show/" + issue['key']
        filename = issue['component'].gsub('.', '/').sub(/.*:/, '') + '.java'
        message = html_escape(issue['message'])
        email += "    <li><a href=\"#{url}\">#{filename}:#{issue['line']}</a>: #{message}</li>\n"
        issues_found = true
      end

      email += <<END
  </ul>
</p>
<p>Please note that Sonar is just a tool
and some of these issues may be false-positives.
If you disagree with any of the issues raised by Sonar, please
consider reconfiguring the rule set (email RTB about any changes)
or adding an explicit ignore rule or a code comment.
</p>
<p>Only those issues which are attributed to lines of code added in the above
commit(s) are included here. This may include pre-existing issues on
code which you have modified, and it may exclude some issues you have
introduced. Use your judgement.</p>
</body>
</html>
END

      if issues_found
        puts "Sonar issues were introduced by #{author}. Now sending the following email:\n"
        puts email
        send_email(
                   author,
                   "Sonar issues introduced in Jenkins build #{ENV['JOB_NAME']} #{ENV['BUILD_NUMBER']}",
                   email)
      else
        puts "No Sonar issues were introduced by #{author}."
      end
    end
  end
end

command :commit do |c|
  c.syntax = 'commit <hash>...'
  c.summary = 'List issues introduced by the specified commit.'
  c.description = 'List issues introduced by the specified commit.

The script will return all issues which Sonar attributes to lines in the code
which `git blame` attributes to the specified commit(s).

If the commits are old, then some of their lines may have since been modified, so
Sonar may have issues attributed to those lines which were not actually caused by
those commits.

I have noticed that Sonar is sometimes a little funny about which line number an
issue belongs to. I think it\'s trying to track issues which move slightly when
their line is moved by a change. This may sometimes result in incorrect results
from the script.'
  c.example '1', "#{$0} commit --project my:project 9bf5886 64a6004"
  c.option '--project STRING', String, 'The Sonar project key, e.g. "my:project" (listed on the main page for the project in Sonar)'

  c.action do |args, options|
    raise '--project is required' unless options.project

    each_issue_for_commits(options.project, args) do |issue|
      url = "http://sonar.zoo.lan/issue/show/" + issue['key']
      filename = issue['component']
      puts "#{filename}:#{issue['line']} [sonar|#{url}]: #{issue['message']}"
      puts
    end
  end
end

# When running inside a Jenkins build, this returns the hashes of all commits
# included in the current build as a list of strings (may be empty).
# See http://stackoverflow.com/questions/6260383/how-to-get-list-of-changed-files-since-last-build-in-jenkins-hudson
def get_commit_list_for_current_jenkins_build
  build_url = ENV['BUILD_URL'] or raise "Missing ENV var 'BUILD_URL'"
  url = build_url + 'api/json/'
  build_json = Net::HTTP.get_response(URI.parse(url)).body
  build = JSON.parse(build_json)

  commits = []
  build['changeSet']['items'].each do |item|
    commits << item['id']
  end
  commits
end

def get_repo
  @repo ||= Rugged::Repository::new(Rugged::Repository::discover())
end

# Yields an issue object for each issue created in the given commits
def each_issue_for_commits project_name, hashlist, &block
  hashlist.each do |revhash|
    repo = get_repo()

    commit = repo.lookup(revhash)
    diff = commit.parent.diff(commit)
    diff.each_patch do |patch|

      # Get the added lines
      lines = Set.new
      patch.each_hunk do |hunk|
        hunk.each_line do |line|
          if line.addition?
            lines << line.new_lineno
          end
        end
      end

      # Get the current issues for the file
      delta = patch.delta
      filename = delta.new_file[:path]

      sonar_resource_name = project_name + ':' +
        filename.sub(SRC_PREFIX_REGEX, '') \
        .sub(/.java$/, '') \
        .gsub('/', '.')

      # http://docs.codehaus.org/pages/viewpage.action?pageId=231080558#WebService/api/issues-GetaListofIssues
      url = "http://sonar.zoo.lan:9000/api/issues/search?components=#{sonar_resource_name}"
      issues_json = Net::HTTP.get_response(URI.parse(url)).body
      all_issues = JSON.parse(issues_json)

      new_issues = all_issues['issues'].select { |issue| lines.include? issue['line'] }

      # print the result
      new_issues.each &block
    end
  end
end

def get_author_email revhash
  repo = get_repo()
  commit = repo.lookup(revhash)
  commit.author[:email]
end

class Rugged::Commit
  def parent
    ps = parents
    raise "multiple parents" unless parents.count == 1
    ps.first
  end
end

def get_password(prompt="Enter Password")
  # Highline doesn't work in cygwin bash
  if ENV['SHELL']
    puts prompt
    password = $stdin.gets.chomp
    puts "\033[2A"
    puts ("*" * password.length) + "\r"
    password
  else
    ask(prompt) {|q| q.echo = false}
  end
end

def html_escape string
  CGI.escapeHTML string
end

def send_email address, subject, body
  from = 'jenkins-master@zoo.lan'

  message = <<END
From: #{from}
To: #{address}
MIME-Version: 1.0
Content-type: text/html
Subject: #{subject}

#{body}
END

  Net::SMTP.start('smtp.zoo.lan') do |smtp|
    smtp.send_message message, from, address
  end
end

# Creates a short log for each commit hash, and sorts them
def commit_summaries_from_hashes commit_hashes
  repo = get_repo()
  commits = commit_hashes.map {|hash| repo.lookup(hash)}
  commits.sort! {|a,b| a.time <=> b.time }

  author_max_len = commits.map {|commit| commit.author[:name].length }.max

  commits.map do |commit|
    message_first_line = commit.message[/.*/]

    "#{commit.oid[0,7]} #{commit.author[:name].ljust(author_max_len)} #{message_first_line}"
  end
end
