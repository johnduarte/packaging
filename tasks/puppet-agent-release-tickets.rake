# This rake task creates tickets in jira for a puppet-agent release.
# Tasks here differ from single-component releases in that they apply
# to multiple components - each project which is being updated for
# the new puppet-agent version.

def get_agent_release_ticket_vars
  vars = {}

  # roles
  vars[:builder]         = Pkg::Util.get_var("BUILDER")
  vars[:developer]       = Pkg::Util.get_var("DEVELOPER")
  vars[:writer]          = Pkg::Util.get_var("WRITER")
  vars[:owner]           = Pkg::Util.get_var("OWNER")
  vars[:tester]          = Pkg::Util.get_var("TESTER")
  vars[:project_manager] = Pkg::Util.get_var("PROJECT_MANAGER")

  # Component releases
  vars[:project] = 'PA'
  vars[:puppet_agent_release] = Pkg::Util.get_var("PUPPET_AGENT_RELEASE")
  vars[:puppet_release]       = Pkg::Util.get_var("PUPPET_RELEASE")
  vars[:facter_release]       = Pkg::Util.get_var("FACTER_RELEASE")
  vars[:hiera_release]        = Pkg::Util.get_var("HIERA_RELEASE")
  vars[:mcollective_release]  = Pkg::Util.get_var("MCOLLECTIVE_RELEASE")
  vars[:pcp_release]          = Pkg::Util.get_var("PCP_RELEASE")
  vars[:date]                 = Pkg::Util.get_var("DATE")
  # Jira authentication - do this after validating other params, so user doesn't need to
  # enter password only to find out they typo'd one of the above
  vars.merge(Pkg::Util::Jira.get_auth_vars)
end

def validate_agent_release_ticket_vars(jira, vars)
  jira.project vars[:project]
  jira.user vars[:builder]
  jira.user vars[:writer]
  jira.user vars[:developer]
  jira.user vars[:owner]
  jira.user vars[:tester]
end

def create_agent_release_tickets(jira, vars)
  description = {}
  description[:code_ready] = <<-DOC
1) Check that the version number in source for each component is correct for the current release. This should have been done as the last step of the previous release.
  * Puppet: check {{lib/puppet/version.rb}} for the {{PUPPETVERSION}} variable.
  * Facter: check {{lib/CMakeLists.txt}} for the {{LIBFACTER_VERSION}} variables, and ensure the major, minor and patch settings are correct.
  * Hiera: check {{lib/hiera/version.rb}} for the {{VERSION}} variable.
  * Mcollective: check {{lib/mcollective.rb}} for the {{VERSION}} variable.
  * Pxp-agent: check {{CMakeLists.txt}} for the {{APPLICATION_VERSION_STRING}} variable.

2) Check that each component config in the puppet-agent repo points to the correct SHA for the release.
  * The configs are in {{configs/components/*.json}}.
  * Ensure that for each component, there are no new commits between the listed ref and the head of stable. Ensure your stable branch is up to date and use {{git log -pretty=oneline <ref>..stable}} to check for additional commits.
  * Ensure that the {{windows_puppet.json}} and {{windows_ruby.json}} configs point at the correct tags. Generally, the Windows team will have created these tags ahead of time, but this step may require tagging the respective Windows repos if not.
  ** Important! These configs *must* be pointing at actual tags, not SHAs!

3) Once the component configs in puppet-agent are verified to be correct, ensure that every component has successfully gone through CI.
  * First, check https://jenkins.puppetlabs.com/view/All%20in%20One%20Agent/view/Stable/view/Puppet%20Agent%20Daily/ to ensure that the AIO daily job has completed successfully, and that all tests are passing.
  * Next, check http://kahless.delivery.puppetlabs.net/view/pxp-agent/ to ensure that pxp-agent has passed all tests in CI.

4) Ensure that all tickets targeted at this release for all components are resolved.
  * Use the following filter to view all tickets for all components for this release: https://tickets.puppetlabs.com/issues/?jql=fixVersion%20in%20(%22puppet-agent%20#{vars[:puppet_agent_release]}%22%2C%20%22PUP%20#{vars[:puppet_release]}%22%2C%20%22FACT%20#{vars[:facter_release]}%22%2C%20%22HI%20#{vars[:hiera_release]}%22%2C%20%22MCO%20#{vars[:mcollective_release]}%22%2C%20%22PCP%20#{vars[:pcp_release]}%22%29
  * Any tickets which are not resolved should be brought to the attention of the appropriate scrum team so they can be resolved for the release.

DOC

  description[:reconcile_git_jira] = <<-DOC
Use the [ticketmatch|https://github.com/puppetlabs/ticketmatch] script to ensure all tickets referenced in the commit log have a bug targeted at the release, and ensure all tickets targeted at the release have a corresponding commit. This needs to be done for each component, including puppet-agent itself.

  * cd ~/work
  * git clone https://github.com/puppetlabs/ticketmatch
  * cd ~/work/<component> for each of puppet, facter, hiera, marionette-collective, pxp-agent, and puppet-agent
  * ruby ../ticketmatch/ticketmatch.rb
    Enter Git From Rev: <previous version> (i.e, PUP 4.1.0)
    Enter Git To Rev: |master| stable
    Enter JIRA project: |<JIRA project tag>|
    Enter JIRA fix version: <Version to be released> (i.e, PUP 4.2.0)

The output may contain the following headers:

COMMIT TOKENS NOT FOUND IN JIRA (OR NOT WITH FIX VERSION OF ...)

Lists git commits that don't have a corresponding ticket, at least not for the specified fix version. If the commit has a ticket, but the ticket is not targeted correctly, then the ticket's fixVersion should be updated. This can frequently happen if a ticket is initially targeted for a future release (master), but is pulled into an earlier release (stable), but the ticket's fixVersion is not updated.

UNRESOLVED ISSUES NOT FOUND IN GIT

Lists JIRA tickets that have a matching fixVersion, e.g. PUP 4.2.0, but none of the commits have the JIRA ticket in the subject. If the JIRA ticket really is fixed in the release, e.g. the JIRA ticket was typo'ed in the git commit subject, then leave the ticket as is. If the JIRA ticket should not be fixed in the release, e.g. it was originally targeted for the release, but was later bumped out, then update the ticket's fixVersion accordingly, e.g. PUP 4.3.0.

UNRESOLVED ISSUES FOUND IN GIT

Lists JIRA tickets have a git commit, but the ticket is not resolved. Usually this is because the ticket is still passing CI or going through manual validation. It can also occur if a fix is made, but a problem is encountered, and the ticket is reopened. If that happens, make sure the ticket reflects reality, so it's clear the ticket is not actually fixed in the release.

  * Make note in a comment of any tickets in git not found in JIRA (or visa versa) with an explanation of why the ticket is in that state.
DOC

  description[:merge_to_stable] = <<-DOC
For some releases, the code base will need to be merged down to stable.

*NOTE:* This is usually only during a x.y.0 release, but even then it may have already been done. If it doesn't apply, close this ticket.


Assuming you have origin (your remote) and upstream (puppetlabs remote), the commands will look something like this:
{noformat}
git fetch upstream
git rebase upstream/master

git checkout stable
git rebase upstream/stable

git merge master --no-ff --log
{noformat}

Once that looks good:
{noformat}
git push origin
git push upstream
{noformat}

After merging to stable, the jobs on jenkins may require updates (spec, acceptance, etc) when you merge master into stable. Please ensure that the jenkins jobs are updated if necessary.

Note that when merging master into stable, the stable versions of the component config refs should be preferred should there be a merge conflict.

Dependencies:
  * Is the code ready for release?
  * Reconcile git commits and JIRA tickets
  * Update version number in source
DOC

  description[:jira_maintenance] = <<-DOC
This happens in Jira - we need to clean up the current release and prepare for the next release. [~#{vars[:project_manager]}], please do the following:
  * For each component, create a version we can target future issues or issues that didn't make it into the current release. (e.g, if this release includes Puppet 4.2.3, make sure there's a 4.2.4 version (or at least 4.2.x if there isn't another bug release planned for the near future). This often comes down to knowing what our next version release will be, so as around if you're not sure.
  * Create a public pair of queries for inclusion in the release notes/announcement. These allow easy tracking as new bugs come in for a particular version and allow everyone to see the list of changes slated for the next release (Paste their URLs into the "Release story" ticket):
    - We now use one query which includes all puppet-agent components.
    - {{affectedVersion in ("puppet-agent #{vars[:puppet_agent_release]}", "PUP #{vars[:puppet_release]}", "FACT #{vars[:facter_release]}", "HI #{vars[:hiera_release]}", "MCO #{vars[:mcollective_release]}", "PCP #{vars[:pcp_release]}")}}, Save as "Introduced in puppet-agent #{vars[:puppet_agent_release]}", click Details, add permission for Everyone
    - {{fixVersion in ("puppet-agent #{vars[:puppet_agent_release]}", "PUP #{vars[:puppet_release]}", "FACT #{vars[:facter_release]}", "HI #{vars[:hiera_release]}", "MCO #{vars[:mcollective_release]}", "PCP #{vars[:pcp_release]}")}}, Save as "Fixed in puppet-agent #{vars[:puppet_agent_release]}", click Details, add permission for Everyone
DOC

  description[:release_notes] = <<-DOC
Collaborating with product for release story

Once git commits and JIRA tickets have been reconciled and the public JIRA filters exist for the release, mark this ticket as ready for engineering and hand it off to the Docs team.

Dependencies:
  * Reconcile git commits and JIRA tickets
DOC

  description[:tag_package] = <<-DOC
Tag and create packages

1) Developer provides the SHAs for each component of puppet-agent *and* puppet-agent itself.- [~#{vars[:developer]}] please add each SHA in a comment. These should match those in the puppet-agent component configs verified in step 1.

2) [~#{vars[:builder]}]: Do the following for each component of the release which has been updated (i.e, puppet, facter, hiera, etc). This is necessary to ensure gems and tarballs are created for each project.
  * Checkout the provided sha.
    * Make sure you are about to tag the correct thing.
  * Create the tag e.g.) {{git tag -s -u {GPG key} -m "4.2.3" 4.2.3}}
    * You need to know the pass phrase for this to complete successfully. It's important that we make sure all releases are signed to verify authenticity.
  * {{git describe}} will show you the tag. Make sure you're building what you think you're building.
  * Make sure you look over the code that has changed since the previous release so we know what's going out the door.
  * run {{rake package:implode package:bootstrap pl:jenkins:uber_build}} when you've verified what version you're building (this uses the latest version of the packaging repo to build the packages).
  * Push the tag.

3) [~#{vars[:builder]}]: make a pull request against puppet-agent#stable to bump each component to the freshly pushed tags from above:
  {noformat}
{"url": "git://github.com/puppetlabs/puppet.git", "ref": "refs/tags/#{vars[:puppet_release]}"} # puppet.json
{"url": "git://github.com/puppetlabs/facter.git", "ref": "refs/tags/#{vars[:facter_release]}"} # facter.json
... # Other components
  {noformat}

In addition, double check that {{windows_puppet.json}} and {{windows_ruby.json}} include the correct tags.

4) Once the above pull request has been merged, leave a comment in this ticket with the SHA of the merge commit and verify the build succeeds on at least one target with:
{noformat}
$ cd puppet-agent
$ env SSH_VANAGON_KEY=~/.ssh/jenkins bundle exec build puppet-agent el-7-x86_64
{noformat}

  * If the build succeeds, tag puppet-agent as #{vars[:puppet_agent_release]} and kick off a build at https://jenkins.puppetlabs.com/view/All%20in%20One%20Agent/view/Stable/view/Puppet%20Agent%20Daily/job/platform_aio-suite_stage-intn_stable/build?delay=0sec using the default set of parameters.
  * After the build, packages can be found in builds.delivery.puppetlabs.net/puppet-agent/#{vars[:puppet_agent_release]}

Dependencies:
  * Every ticket before this except for release notes.
DOC

  description[:smoke_test] = <<-DOC
Procedure may vary by project and point in the release cycle. Ask around.

Our automated acceptance pipelines generally cover most basic scenarios, so in general we don't need to manually smoke test our packages. We may want to smoke test component tarballs, as they are not automatically tested.

1) Test the new puppet gems
  * {{cd work/puppet/acceptance}}
  * {{rake ci:test:gem #{vars[:puppet_release]}}}
  * When finished, leave a comment indicating so, or alert the team if they fail.

2) Manual package smoketesting
  * If manual testing is desired (not mandatory), packages can be found at: builds.delivery.puppetlabs.net/puppet-agent/#{vars[:puppet_agent_release]}

Dependencies:
  * Tag and create packages
DOC

  description[:go_no_go] = <<-DOC
This should happen Monday-Thursday, before 4pm. We should not be shipping anything on a Friday both. In addition, having the go-no-go meeting completed by 4PM is prerequisite to continuing the release process. If it is not, we'll need to wait until tomorrow to continue.

Get a yes/no for the release from dev, docs, product, qa, releng.

This meeting is informal, over chat, and usually happens right before packages are pushed.
Keep in mind that we typically do not ship releases on Friday.

Dependencies:
  * Smoke testing

Participants:
  * [~#{vars[:developer]}]
  * [~#{vars[:writer]}]
  * [~#{vars[:owner]}]
  * [~#{vars[:tester]}]
  * [~#{vars[:builder]}]
  * Anyone involved in smoke testing or other aspects of the release who is present.
DOC

  description[:push_packages] = <<-DOC
Push packages

1) For all updated components *and* puppet-agent itself, do the following. This ensures that tarballs and gems are pushed for the component projects, and that the new puppet-agent package is shipped.
  * run {{rake pl:jenkins:uber_ship}}
    * You will need the keys to the castle (aka the passphrase) for this to work.
    * Don't forget to make sure everything looks like it's in the correct folder, the pkgs dir has been cleared out, and that you are shipping for all expected platforms.
    * Get a *second set of RelEng eyes* on the packages that are about to be shipped to make sure everything looks a-okay.
    * If you're shipping a gem you need to make sure you have a rubygems account, are an owner of that project, and have a gem config file.
    * The puppet-agent MSI for Windows needs to be manually signed.
    ** The signed MSIs need to replace the MSIs listed at builds.delivery.puppetlabs.net/puppet-agent/#{vars[:puppet_agent_release]}/shipped/windows/*.msi, but only after the ship task has been completed.
    ** The signed MSIs also need to be manually sent to downloads.puppetlabs.com:/opt/downloads/windows, and permissions need to be verified.
    ** This is a manual process and the ship task doesn't ship or build the msi so talk to Melissa, Morgan or Ryan for more details.
    ** RE-4364 has been filed to automate signing and shipping MSIs. This step can be removed when it is completed.

2) Verify that each component has had the correct bits pushed by the uber_ship. I.e, http://builds.puppetlabs.lan/puppet/#{vars[:puppet_release]}/shipped/ should include the gems and the tarball.

3) [~#{vars[:builder]}]: update the release google spreadsheet.

Dependencies:
  * Go / No Go meeting (Status - Ship it!)
DOC

  description[:push_docs] = <<-DOC
Push the documentation updates to docs.puppetlabs.com.

Dependencies:
  * Go / No Go meeting (Status - Ship it!)
DOC

  description[:send_announcements] = <<-DOC
  * Send the drafted release notes email.
    * If final send to puppet-announce and specific distribution lists (e.g. puppet to puppet-users & puppet-dev).
    * If this release has security implications, also send the release announcement to puppet-security-announce
  * Make a PSA on IRC letting those kiddos know about the new release.
    * Something along the lines of "PSA: puppet-agent #{vars[:puppet_agent_version]} now available"

Dependencies:
  * Prepare long form release notes and short form release story
  * Packages pushed
DOC

  description[:close_tickets] = <<-DOC
Close any tickets that have been resolved for the release, and mark the versions as resolved.

https://tickets.puppetlabs.com/issues/?jql=((project%20%3D%20PUP%20AND%20fixVersion%20%3D%20%22PUP%20#{vars[:puppet_release]}%22)%20OR%20(project%20%3D%20FACT%20AND%20fixVersion%20%3D%20%22FACT%20#{vars[:facter_release]}%22)%20OR%20(project%20%3D%20HI%20AND%20fixVersion%20%3D%20%22HI%20#{vars[:hiera_release]}%22)%20OR%20(project%20%3D%20MCO%20AND%20fixVersion%20%3D%20%22MCO%20#{vars[:mcollective_release]}%22)%20OR%20(project%20%3D%20PCP%20AND%20fixVersion%20%3D%20%22PCP%20#{vars[:pcp_release]}%22)%20OR%20(project%20%3D%20PA%20AND%20fixVersion%20%3D%20%22puppet-agent%20#{vars[:puppet_agent_release]}%22))%20AND%20status%20%3D%20Resolved

1) There is a bulk edit at the top (a gear with the word "Tools"). Should you decide to take this route:
  * Select Bulk Change - All # issues
  * Step 1 - choose all relevant issues (likely all of them)
  * Step 2 - Select "Transition Issues"
  * Step 3 - Select "Closed"
  * Step 4 - Select "Fixed" in Change Resolution.
  * View what is about to change and confirm it. Then commit the change.

2) Make all tickets marked as internal in this release public. Use the following filter to view all tickets still marked as internal in this release:

https://tickets.puppetlabs.com/issues/?jql=((project%20%3D%20PUP%20AND%20fixVersion%20%3D%20%22PUP%20#{vars[:puppet_release]}%22)%20OR%20(project%20%3D%20FACT%20AND%20fixVersion%20%3D%20%22FACT%20#{vars[:facter_release]}%22)%20OR%20(project%20%3D%20HI%20AND%20fixVersion%20%3D%20%22HI%20#{vars[:hiera_release]}%22)%20OR%20(project%20%3D%20MCO%20AND%20fixVersion%20%3D%20%22MCO%20#{vars[:mcollective_release]}%22)%20OR%20(project%20%3D%20PCP%20AND%20fixVersion%20%3D%20%22PCP%20#{vars[:pcp_release]}%22)%20OR%20(project%20%3D%20PA%20AND%20fixVersion%20%3D%20%22puppet-agent%20#{vars[:puppet_agent_release]}%22))%20AND%20status%20%3D%20Resolved%20AND%20level%20in%20%28Internal%2CConfidential%29

3) Once all tickets have been closed and made public, mark each component version going out as "Released" in the Project Admin -> Versions panel.
  * Ping Kenn Hussey or Steve Barlow to mark the puppet-agent version as released.

Dependencies:
  * Packages pushed
DOC

  description[:update_version_source] = <<-DOC
Bump the version number in source for each component in preparation for the next release.

  For each component, commit the updated version file in stable and merge it up into master:
  * Puppet: In {{lib/puppet/version.rb}}, update the {{PUPPETVERSION}} variable.
  * Facter: In {{lib/CMakeLists.txt}}, update each of the {{LIBFACTER_VERSION}} variables, and ensure the major, minor and patch settings are correct. In addition, update the {{PROJECT_NUMBER}} variable in {{lib/Doxyfile}}.
  * Hiera: In {{lib/hiera/version.rb}}, update the {{VERSION}} variable.
  * Mcollective: In {{lib/mcollective.rb}}, update the {{VERSION}} variable.
  * Pxp-agent: In {{CMakeLists.txt}}, update the {{APPLICATION_VERSION_STRING}} variable.

Dependencies:
  * The release has been shipped.
DOC

  description[:disable_pe_promotion] = <<-DOC
Disable auto-promotion into PE from puppet-agent stable.

* Go to https://jenkins.puppetlabs.com/view/All%20in%20One%20Agent/view/Stable/view/Puppet%20Agent%20Daily/job/platform_aio-suite_pkg-promote_stable-pe/ and click the 'Disable' button.

Dependencies
  * The release has been shipped.
DOC

  # The subtickets to create for the individual tasks
  subtickets =
  [
    {
      :summary     => 'Is the code ready for release?',
      :description => description[:code_ready],
      :assignee    => vars[:developer]
    },
    {
      :summary     => 'Reconcile git commits and JIRA tickets',
      :description => description[:reconcile_git_jira],
      :assignee    => vars[:developer]
    },
    {
      :summary     => 'Merge master into stable',
      :description => description[:merge_to_stable],
      :assignee    => vars[:developer]
    },
    {
      :summary     => 'Is the Jira tidy-up done for this release and prepared for the next one?',
      :description => description[:jira_maintenance],
     :assignee     => vars[:project_manager]
    },
    {
      :summary     => 'Prepare long form release notes and short form release story',
      :description => description[:release_notes],
      :assignee    => vars[:writer]
    },
    {
      :summary     => 'Tag the release and create packages',
      :description => description[:tag_package],
      :assignee    => vars[:builder]
    },
    {
      :summary     => 'Smoke test packages',
      :description => description[:smoke_test],
      :assignee    => vars[:developer]
    },
    {
      :summary     => 'Go/no-go meeting (before 4pm)',
      :description => description[:go_no_go],
      :assignee    => vars[:developer]
    },
    {
      :summary     => 'Packages pushed',
      :description => description[:push_packages],
      :assignee    => vars[:builder]
    },
    {
      :summary     => 'Docs pushed',
      :description => description[:push_docs],
      :assignee    => vars[:writer]
    },
    {
      :summary     => 'Send out announcements',
      :description => description[:send_announcements],
      :assignee    => vars[:owner]
    },
    {
      :summary     => 'Close all resolved tickets in Jira',
      :description => description[:close_tickets],
      :assignee    => vars[:developer]
    },
    {
      :summary     => 'Update version number in source',
      :description => description[:update_version_source],
      :assignee    => vars[:developer]
    },
    {
      :summary     => 'Disable PE auto-promotion',
      :description => description[:disable_pe_promotion],
      :assignee    => vars[:developer]
    },

  ]

  # Add redundant (but very useful in emails and tab titles) info to subtask
  # summaries / descriptions.
  subtickets.each {|t|
    t[:summary] << " (#{vars[:project]} #{vars[:puppet_agent_release]})"
    t[:description] = "(Initial planned release date: #{vars[:date]})\n\n" + t[:description]
  }

  # Use the human-friendly project name in the summary
  summary = "#{Pkg::Config.project} #{vars[:puppet_agent_release]} #{vars[:date]} Release"
  description[:top_level_ticket] = <<-DOC
#{summary}

When working through this ticket, add it to the board and then keep it in the Ready for Engineering column.
Move the subtasks to In Progress when you are working on them and Resolved when you have completed them.
In general subtasks should only be moved to Ready for Engineering when they are ready to be worked on. For some assignees this is their cue to start working on release-related items.

 * The first set of tickets are assigned to the developer, those can all be converted to Ready for Engineering and you can start working through them.
 * Only when those are done should you move the "Prepare notes" and "Tag release/create packages" tasks to Ready for Engineering. Ping those assigned to move forward.
 * When you hear back for "Tag Release/create packages", you should move "Smoke test packages" to Ready for Engineering or In Progress if you are ready.
DOC

  # Values for the main ticket
  project  = vars[:project]
  assignee = vars[:developer]

  main_ticket_hash = {
    :summary => summary,
    :description => description[:top_level_ticket],
    :project => project,
    :assignee => assignee,
  }

  # Create the main ticket
  parent_key, parent_id = jira.create_issue(main_ticket_hash)
  puts parent_id
  puts "Main release ticket: #{parent_key} (#{assignee}) - #{summary}"

  # Create subtasks for each step of the release process
  subticket_idx = 1
  release_tickets = []
  subtickets.each do |subticket|

    next if subticket[:projects] && !subticket[:projects].include?(vars[:project])

    subticket[:project] = project
    subticket[:parent] = parent_key

    key, _ = jira.create_issue(subticket)
    puts "\tSubticket #{subticket_idx.to_s.rjust(2)}: #{key} (#{subticket[:assignee]}) - #{subticket[:summary]}"

    release_tickets << key if subticket[:assignee] == vars[:builder]

    subticket_idx += 1
  end

  # Create an RE ticket for this release so the RE team can plan
  release_ticket = {
    :summary => "Release #{Pkg::Config.project} #{vars[:puppet_agent_release]} (#{vars[:date]})",
    :project => 'RE',
    :assignee => vars[:builder],
  }

  release_key, _ = jira.create_issue(release_ticket)

  release_tickets.each do |ticket|
    Pkg::Util::Jira.link_issues(ticket, release_key, vars[:site], Pkg::Util.base64_encode("#{vars[:username]}:#{jira.client.options[:password]}"))
  end
end

namespace :pl do
  desc <<-EOS
Make release tickets in JIRA for puppet-agent.
Tickets are created by specifying a number of environment variables, e.g.:

    rake pl:tickets BUILDER=melissa DEVELOPER=kylo WRITER=nick.fagerlund OWNER=eric.sorenson TESTER=john.duarte PROJECT_MANAGER=steven.barlow PUPPET_AGENT_RELEASE=1.2.7
        PUPPET_RELEASE=4.2.3 FACTER_RELEASE=3.1.1 HIERA_RELEASE=3.0.4 MCOLLECTIVE_RELEASE=2.8.6 PCP_RELEASE=0.0.1
        DATE=2014-04-01 JIRA_USER=kylo

The BUILDER/DEVELOPER/WRITER/OWNER/TESTER/PROJECT_MANAGER params must be valid jira usernames.

Because puppet-agent releases involve the release of multiple sub-components, RELEASE parameters are needed for each. This allows filters
to be auto-generated. These parameters are freeform strings, so no validation is done against them.

The DATE param is a predicted date that this release ticket will be started. This
  is a hint to Release Engineering about when to prep for the release, but not a
  binding contract to release on that date.

The JIRA_USER parameter is used to login to jira to create the tickets. You will
  be prompted for a password. It will not be displayed.
EOS

  task :puppet_agent_release_tickets do
    vars = get_agent_release_ticket_vars
    jira = Pkg::Util::Jira.new(vars[:username], vars[:site])
    validate_release_ticket_vars(jira, vars)

    puts "Creating release tickets based on:"
    require 'pp'
    pp vars.select { |k, v| k != :password }

    create_agent_release_tickets(jira, vars)
  end
end

