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
