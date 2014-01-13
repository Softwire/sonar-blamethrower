sonar-blamethrower
==================

This command line app links Sonar, Crucible and Jenkins
Run `./sonar_blamethrower.rb help` for usage instructions

Installation
------------

You'll need Ruby and Bundler.

If you don't have Ruby, see [http://rubyinstaller.org/](http://rubyinstaller.org/)

Clone the source code, then run:

    gem install bundle
    bundle install

Then run the app with:

    ./sonar_blamethrower.rb help


Windows Problems
----------------

As of 2014-01-09, Cygwin Ruby cannot compile the "rugged" gem. You will need to use the Windows native Ruby installer if you use Cygwin on Windows.
(Note that the Windows native Ruby is recommended anyway for Cygwin users, since it is faster and more reliable than the linux version compiled under Cygwin.)

Also, Rugged 0.19.0 doesn't install cleanly on some versions of Windows.
If you get an error to do with `invalid argument` on Rugged `test/fixture/status`, then you need to open `C:\Ruby193\lib\ruby\gems\1.9.1\cache\rugged-0.19.0.gem` in 7zip and delete the `data.tar.gz\data.tar\test\fixtures\status\??` file then try `bundle install` again.

It looks like this is already fixed in the next version of Rugged.

Features
======

List issues introduced by the specified commit.
------

Get a list of the Sonar issues which the tool thinks can be attributed to a specific commit or commits with a command like

    ./sonar-blamethrower.rb commit --project my:project 9bf5886 64a6004

You will need to look up your "project key" from Sonar (it is listed on the main page for the project in Sonar like "Key:   my:project").

For more documenation, try 

      ./sonar-blamethrower.rb help commit

### Remarks and Known Issues

The script will return all issues which Sonar attributes to lines in the code which `git blame` attributes to the specified commit(s). 

If the commits are old, then some of their lines may have since been modified, so Sonar may have issues attributed to those lines which were not actually caused by those commits.

List issues introduced in the specified Crucible review.
------

Get a list of the Sonar issues which the tool thinks can be attributed to a specific Crucible review with a command like

    ./sonar-blamethrower.rb review --project my:project CR-ABC-370

You will need to look up your "project key" from Sonar (it is listed on the main page for the project in Sonar like "Key:   my:project").

For more documenation, try 

      ./sonar-blamethrower.rb help review

### Remarks and Known Issues

The script consults Crucible to establish which commits belong to the specified review (it will prompt you for your Crucible password), and then proceeds just as in the `commit` case. See the remarks on `help commit` for more.

The logic to establish which commits belong to a review does not work all that well. See the extended discussion at [https://answers.atlassian.com/questions/235556/crucible-get-list-of-changesets-revisions-in-a-review](https://answers.atlassian.com/questions/235556/crucible-get-list-of-changesets-revisions-in-a-review)


Email authors about new issues during a Jenkins build
------

Run this command during a Jenkins build, and after the Sonar plugin has run. It will determine which changes are included in the current build, look up whether any new Sonar issues were introduced by those changes, and email the authors with the details.

    ./sonar-blamethrower.rb jenkins --project my:project

You will need to look up your "project key" from Sonar (it is listed on the main page for the project in Sonar like "Key:   my:project").

For more documenation, try 

      ./sonar-blamethrower.rb help jenkins

### Remarks and Known Issues

The script consults the Jenkins environment variables and XML API to establish which commits belong to the currently running build, and then proceeds just as in the `commit` case. See the remarks on `help commit` for more.

You should run this command after the Sonar analysis step in your build process, otherwise Sonar won't have the correct details.
