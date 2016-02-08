<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Test scripts and build framework for iX projects](#test-scripts-and-build-framework-for-ix-projects)
- [FreeNAS Builds](#freenas-builds)
  - [iso](#iso)
  - [tests](#tests)
  - [all](#all)
- [PC-BSD Builds](#pc-bsd-builds)
  - [all](#all-1)
  - [world](#world)
  - [ports](#ports)
  - [ports-meta-only](#ports-meta-only)
  - [ports-update-all](#ports-update-all)
  - [ports-update-pcbsd](#ports-update-pcbsd)
  - [image](#image)
  - [menu](#menu)
  - [clean](#clean)
  - [vm](#vm)
- [Jenkins Automation](#jenkins-automation)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

Test scripts and build framework for iX projects
===========

Scripts for the following

 * PC-BSD Builds -  ISO / regression test
 * FreeNAS Builds - ISO / regression test
 * Jenkins automation

FreeNAS Builds
============

Getting Started:

First, cd to the "freenas" sub-directory and make a copy of the following:

freenas.cfg.dist -> freenas.cfg

Next, you will want to edit freenas.cfg and check that the options are correct
for the version of FreeNAS you plan on building.

Once that file is created with the correct values, you can run the following
"make" commands to start a build:

iso
---
Build FreeNAS ISOs / update files from sources, this may take a while.

all
---
Create the ISO files and run the testing framework to check for regressions

tests
---
Run the regression testing framework. Will generate auto-install ISOs and
install them into a VM for testing purposes.

Tests are located in the freenas/scripts/9.3-tests.sh and
freenas/scripts/10-tests.sh files. These scripts can also be run directly
by pointing them at a FreeNAS instance with the following syntax:

```
 # cd freenas/scripts && ./9.3-tests.sh
```

```
 *Optional* arguments to 9.3-tests.sh

 testset={smoke|complete|benchmark}

     smoke - Basic tests to check core functionality
  complete - More in-depth testing to check edge cases
 benchmark - Run tests which measure speeds

 module={smb|nfs|ftp|etc|etc}

   The various modules you want to run, multiple module= lines allowed. If not specified all
tests will be run.

 ip=<hostip>

 FreeNAS host/IP address

 user=<FreeNASUsername>

 FreeNAS username for REST auth

 password=<FreeNASpassword>

 FreeNAS password for REST auth
```

FreeNAS Testing Framework
============

Adding New tests
---

New tests can be written for FreeNAS 9.3.X by adding a test "module" to the 9.3 testing directory:

https://github.com/iXsystems/ix-tests/tree/master/freenas/9.3-tests

By setting REQUIRES="storage" you can list other testing modules which must be run before yours, I.E. "storage"
may be required to setup a zpool / dataset to perform testing of shares.


Where are tests run?
---

The tests for FreeNAS 9.3.X are currently being run on-commit. Committers will automatically get
an e-mail with results and log files on testing failures.

Tests / log output can be viewed at the following location:
https://builds.pcbsd.org/jenkins/view/FreeNAS%20ATF/



PC-BSD Builds
============

This program will do the compile of a FreeBSD world / kernel, 
fetch packages from the PC-BSD PKGNG CDN and assemble an ISO file. 

Requirements:

 - FreeBSD 10.1 or higher
 - A PKGNG repo for the target version / arch
 - git
 - zip
 - grub-mkrescue
 - xorriso
 - poudriere (optional)
 - unicode.pf2 (required for grub-mkrescue)

Getting Started:

First, cd to the "pcbsd" sub-directory and make a copy of the following:

```
# cp pcbsd.cfg.dist pcbsd.cfg
# cp -R pkg-dist/ pkg/
# cp -R pbi-dist/ pbi/
```

Next, you will want to edit pcbsd.cfg and check that the options are correct
for the version of PC-BSD you plan on building.

If you will be building the entire pkg repo (default) then the system will
need to have poudriere installed and configured to be ready for building.
If you are building a custom PC-BSD, you may wish to replace the pkg/pbi
paths and keys in pkg/ and pbi/ directories. 

To start a build, run "make" in the source directory. FreeBSD sources will be 
downloaded from GIT automatically, and then a world / kernel built. Once
this build finishes, the builder will begin compiling packages with poudriere.
Lastly the ISO will be built in the ~/iso directory.


Advanced Usage:

The following "make" targets are available:

all
---

Will create the FreeBSD world, fetch packages or build ports from poudriere,
and then assemble an ISO file.

world
---

Will update the FreeBSD git repo and rebuild the FreeBSD world environment

ports
---

Will rebuild the local ports / pkgng repo, using poudriere, if enable in
pcbsd.cfg

ports-meta-only
---

Will do a poudriere build of just the PC-BSD specific meta-ports for creating
an ISO file, not the entire ports tree

ports-update-all
---

Will update the ports tree used by poudriere with portsnap and the pcbsd
build-files/ports-overlay directory in git.

ports-update-pcbsd
---

Will update the ports tree used by poudriere with the latest in the pcbsd
build-files/ports-overlay directory in git.

image
---

Will create a new ISO file from the local FreeBSD dist files and packages
from either local poudreire or remote PKGNG repo.

menu
---

Will launch a dialog-based menu with access to all the listed make targets

clean
---

Will cleanup any temp files in ${PROGDIR}/tmp

vm
---

Will create VM images of PC-BSD / TrueOS for VirtualBox / VMWare and raw disk



Jenkins Automation
============

Jenkins helper automation scripts, these are used by PC-BSD to handle
the running of jobs from Jenkins on any random builder, while storing
temp files and finished products on another system for easy access.

Usage:

Copy build.conf.dist -> build.conf and set the values for your storage server
to allow nodes to run sftp and sync data between them. Your nodes will need
to have SSH setup to access this system already. 

./jenkins.sh world/jail/ports/iso/vm/freenas/freenas-tests version edge/production
