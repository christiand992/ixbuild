#!/bin/sh

# Set the repo we pull for build / tests
GITREPO="https://github.com/iXsystems/ixbuild.git"
# Set the branch to use for above repo
if [ -z "$IXBUILDBRANCH" ] ; then
  IXBUILDBRANCH="master"
fi

cleanup_workdir()
{
  if [ -z "$MASTERWRKDIR" ] ; then return 0; fi
  if [ ! -d "$MASTERWRKDIR" ] ; then return 0 ; fi
  if [ "$MASTERWRKDIR" = "/" ] ; then return 0 ; fi

  # Cleanup any leftover mounts
  for i in `mount | grep -q "on ${MASTERWRKDIR}/" | awk '{print $1}' | tail -r`
  do
    umount -f $i
  done

  # Should be done with unmounts
  mount | grep -q "on ${MASTERWRKDIR}/"
  if [ $? -ne 0 ] ; then
    rm -rf ${MASTERWRKDIR} 2>/dev/null
    chflags -R noschg ${MASTERWRKDIR} 2>/dev/null
    rm -rf ${MASTERWRKDIR}
  fi
  cd
}

exit_clean()
{
  cleanup_workdir
  exit 1
}

create_workdir()
{
  if [ ! -d "/tmp/build" ] ; then
     mkdir /tmp/build
  fi
  cd /tmp/build

  MASTERWRKDIR=`mktemp -d /tmp/build/XXXX` 

  cocmd="git clone --depth=1 -b ${IXBUILDBRANCH} ${GITREPO} ${MASTERWRKDIR}"
  echo "Cloning with: $cocmd"
  $cocmd
  if [ $? -ne 0 ] ; then exit_clean; fi

  cd ${MASTERWRKDIR}
  if [ $? -ne 0 ] ; then exit_clean; fi

  # Copy over user builds
  if [ -d "/ixbuild/builds" ] ; then
    rm -rf ${MASTERWRKDIR}/builds
    cp -r /ixbuild/builds ${MASTERWRKDIR}/builds
  fi

  echo "$BUILDTAG" | grep -q -e "freenas" -e "truenas"
  if [ $? -eq 0 ] ; then
    TBUILDDIR="${MASTERWRKDIR}/freenas"
  else
    echo "$BUILDTAG" | grep -q "trueos"
    if [ $? -eq 0 ] ; then
      TBUILDDIR="${MASTERWRKDIR}/trueos"
    else
      TBUILDDIR="${MASTERWRKDIR}/pcbsd"
    fi
  fi

  cp ${BDIR}/${BUILD}/* ${TBUILDDIR}
  if [ $? -ne 0 ] ; then exit_clean; fi

  cd ${TBUILDDIR}
  if [ $? -ne 0 ] ; then exit_clean; fi
}

push_pkgworkdir()
{
  cd ${PPKGDIR}
  if [ $? -ne 0 ] ; then exit_clean; fi
  if [ -z "$SFTPHOST" ] ; then return 0; fi

  ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${WORKPKG}" >/dev/null 2>/dev/null

  echo "Pushing cached pkgs..."
  rsync -va --delete -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${WORKPKG}/ >${MASTERWRKDIR}/push.log 2>${MASTERWRKDIR}/push.log
  if [ $? -ne 0 ] ; then tail -50 ${MASTERWRKDIR}/push.log ; exit_clean; fi
}


pull_pkgworkdir()
{
  if [ -z "$SFTPHOST" ] ; then return 0; fi

  # Check if we have any workdirs to re-sync
  ssh ${SFTPUSER}@${SFTPHOST} "ls ${WORKPKG}" >/dev/null 2>/dev/null
  if [ $? -ne 0 ] ; then
     return 0
  fi

  if [ ! -d "${PPKGDIR}" ] ; then
    mkdir -p ${PPKGDIR}
  fi

  cd ${PPKGDIR}
  if [ $? -ne 0 ] ; then exit_clean; fi

  echo "Pulling cached pkgs..."
  rsync -va --delete -e 'ssh' ${SFTPUSER}@${SFTPHOST}:${WORKPKG}/ . >${MASTERWRKDIR}/push.log 2>${MASTERWRKDIR}/push.log

  if [ $? -ne 0 ] ; then tail -50 ${MASTERWRKDIR}/push.log ; exit_clean; fi
}

push_world()
{
  cd ${TBUILDDIR}/fbsd-dist
  if [ $? -ne 0 ] ; then exit_clean; fi

  # Pushing to a local directory?
  if [ -z "$SFTPHOST" ] ; then
    if [ ! -d "${PCBSDBDIR}/fbsd-dist/${WORLDTREL}" ] ; then mkdir -p ${PCBSDBDIR}/fbsd-dist/${WORLDTREL}; fi
    rm ${PCBSDBDIR}/fbsd-dist/${WORLDTREL}/* 2>/dev/null
    echo "Saving FreeBSD dist files -> ${PCBSDBDIR}/fbsd-dist/${WORLDTREL}"
    cp * ${PCBSDBDIR}/fbsd-dist/${WORLDTREL}/
    return 0
  fi

  # Push world packages to work directory
  ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${WORKWORLD}" >/dev/null 2>/dev/null

  rsync -va --delete -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${WORKWORLD}/ >${MASTERWRKDIR}/push.log 2>${MASTERWRKDIR}/push.log
  if [ $? -ne 0 ] ; then tail -50 ${MASTERWRKDIR}/push.log ; exit_clean; fi

  if [ -n "$PKGBASE" ] ; then
    # Push packages to base directory
    cd ${TBUILDDIR}/fbsd-pkg
    ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${PKGSTAGE}-base" >/dev/null 2>/dev/null
    rsync -va --delete -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${PKGSTAGE}-base/ >${MASTERWRKDIR}/push.log 2>${MASTERWRKDIR}/push.log
  fi

  # Dist files to dist directory
  cd ${TBUILDDIR}/fbsd-dist
  ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${ISOSTAGE}/dist" >/dev/null 2>/dev/null
  rsync -va --delete -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${ISOSTAGE}/dist/ >${MASTERWRKDIR}/push.log 2>${MASTERWRKDIR}/push.log
}

pull_world()
{
  if [ ! -d "${TBUILDDIR}/fbsd-dist" ] ; then
    mkdir -p ${TBUILDDIR}/fbsd-dist
  fi

  # Pulling from a local dist set
  if [ -z "$SFTPHOST" ] ; then
    if [ ! -d "${PCBSDBDIR}/fbsd-dist/${WORLDTREL}" ] ; then return 1; fi
    cp ${PCBSDBDIR}/fbsd-dist/${WORLDTREL}/* ${TBUILDDIR}/fbsd-dist/
    if [ $? -ne 0 ] ; then
      return 1
    fi
    return 0
  fi

  # Pulling from a remote dist set

  # Check if the world exists
  ssh ${SFTPUSER}@${SFTPHOST} "ls ${WORKWORLD}" >/dev/null 2>/dev/null
  if [ $? -ne 0 ] ; then
     return 1
  fi

  if [ -n "$PKGBASE" ] ; then
    # Push packages to base directory
    mkdir ${TBUILDDIR}/fbsd-pkg
    cd ${TBUILDDIR}/fbsd-pkg
    if [ $? -ne 0 ] ; then exit_clean; fi
    echo "Pulling base packages..."
    rsync -va --delete -e 'ssh' ${SFTPUSER}@${SFTPHOST}:${PKGSTAGE}-base/ . >${MASTERWRKDIR}/push.log 2>${MASTERWRKDIR}/push.log
  fi

  cd ${TBUILDDIR}/fbsd-dist
  if [ $? -ne 0 ] ; then exit_clean; fi

  rsync -va --delete -e 'ssh' ${SFTPUSER}@${SFTPHOST}:${WORKWORLD}/ . >${MASTERWRKDIR}/push.log 2>${MASTERWRKDIR}/push.log
  if [ $? -ne 0 ] ; then tail -50 ${MASTERWRKDIR}/push.log ; exit_clean; fi
  return 0
}

pull_iso()
{
  if [ -z "$SFTPHOST" ] ; then return 0; fi

  # Check if we have any workdirs to re-sync
  ssh ${SFTPUSER}@${SFTPHOST} "ls ${ISOSTAGE}" >/dev/null 2>/dev/null
  if [ $? -ne 0 ] ; then
     return 0
  fi

  if [ ! -d "${TBUILDDIR}/iso" ] ; then
    mkdir -p ${TBUILDDIR}/iso
  fi

  cd ${TBUILDDIR}/iso
  if [ $? -ne 0 ] ; then exit_clean; fi

  rsync -va --delete -e 'ssh' ${SFTPUSER}@${SFTPHOST}:${ISOSTAGE}/ . >${MASTERWRKDIR}/push.log 2>${MASTERWRKDIR}/push.log
  if [ $? -ne 0 ] ; then tail -50 ${MASTERWRKDIR}/push.log ; exit_clean; fi
}

jenkins_world()
{
  create_workdir

  cd ${TBUILDDIR}
  if [ $? -ne 0 ] ; then exit_clean; fi

  make world
  if [ $? -ne 0 ] ; then exit_clean; fi

  push_world

  if [ -z "$1" ] ; then
    cleanup_workdir
  fi
}

jenkins_jail()
{
  create_workdir

  pull_world
  if [ $? -ne 0 ] ; then
    jenkins_world "1"
    pull_world
    if [ $? -ne 0 ] ; then
       exit_clean "Failed getting world files"
    fi
  fi

  cd ${TBUILDDIR}
  if [ $? -ne 0 ] ; then exit_clean; fi

  make jail
  if [ $? -ne 0 ] ; then exit_clean; fi

  cleanup_workdir

  exit 0
}

jenkins_pkg()
{
  create_workdir

  # Pull in the world directory
  pull_world
  if [ $? -ne 0 ] ; then
    jenkins_world "1"
    pull_world
    if [ $? -ne 0 ] ; then
       exit_clean "Failed getting world files"
    fi
  fi

  cd ${TBUILDDIR}
  if [ $? -ne 0 ] ; then exit_clean; fi

  # Check if we have a more current pkg set on the local box
  if [ -n "$SFTPHOST" ] ; then
    remotetime=`ssh ${SFTPUSER}@${SFTPHOST} "cat ${PKGSTAGE}/.started" 2>/dev/null`
    localtime=`cat ${PPKGDIR}/.started 2>/dev/null`
    if [ -n "$remotetime" -a -n "$localtime" ] ; then
      if [ $remotetime -lt $localtime ] ; then
        push_pkgworkdir
      fi
    fi
  fi

  cd ${TBUILDDIR}
  make ports-update-all
  if [ $? -ne 0 ] ; then exit_clean; fi

  # Pull the workdir from the cache
  pull_pkgworkdir

  cd ${TBUILDDIR}
  if [ $? -ne 0 ] ; then exit_clean; fi

  # Save the timestamp of when we started this poud run
  if [ ! -d "${PPKGDIR}" ] ; then mkdir -p ${PPKGDIR} ; fi
  date +"%s" >${PPKGDIR}/.started

  # Make the release or ISO packages
  if [ "$1" = "release" ] ; then
    make ports
    if [ $? -ne 0 ] ; then push_pkgworkdir; exit_clean; fi
  else
    make iso-ports
    if [ $? -ne 0 ] ; then push_pkgworkdir; exit_clean; fi
  fi

  # Push over the workdir to the cache
  push_pkgworkdir

  # Yay, success! Lets rsync the package set to staging machine
  cd $PPKGDIR
  if [ $? -ne 0 ] ; then exit_clean; fi

  if [ -n "$SFTPHOST" ] ; then
    ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${PKGSTAGE}" >/dev/null 2>/dev/null

    rsync -va --delete -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${PKGSTAGE} >${MASTERWRKDIR}/push.log 2>${MASTERWRKDIR}/push.log
    if [ $? -ne 0 ] ; then tail -50 ${MASTERWRKDIR}/push.log ; exit_clean; fi
  fi

  cleanup_workdir

  exit 0
}

jenkins_iso()
{
  create_workdir

  pull_world

  # Pull the workdir from the cache
  pull_pkgworkdir

  cd ${TBUILDDIR}
  if [ $? -ne 0 ] ; then exit_clean; fi

  make image
  if [ $? -ne 0 ] ; then exit_clean; fi

  # Now lets sync the ISOs
  cd ${TBUILDDIR}/iso
  if [ $? -ne 0 ] ; then exit_clean; fi

  if [ -n "$SFTPHOST" ] ; then
    ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${ISOSTAGE}" >/dev/null 2>/dev/null
    rsync -va --delete -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${ISOSTAGE} >${MASTERWRKDIR}/push.log 2>${MASTERWRKDIR}/push.log
    if [ $? -ne 0 ] ; then tail -50 ${MASTERWRKDIR}/push.log ; exit_clean; fi
  fi

  cleanup_workdir

  exit 0
}

jenkins_publish_pkg()
{
  if [ ! -d "${SFTPFINALDIR}/pkg/${TARGETREL}" ] ; then
    echo "Missing packages to push!"
    exit 1
  fi

  # Set target locations
  scale="pcbsd@pcbsd-master.scaleengine.net"
  target="/usr/home/pcbsd/mirror/pkg"

  # Make sure remote target exists
  echo "ssh ${scale} mkdir -p ${target}/${TARGETREL}"
  ssh ${scale} "mkdir -p ${target}/${TARGETREL}" >/dev/null 2>/dev/null

  # Copy packages
  rsync -va --delete-delay --delay-updates -e 'ssh' ${SFTPFINALDIR}/pkg/${TARGETREL}/ ${scale}:${target}/${TARGETREL}/
  if [ $? -ne 0 ] ; then exit_clean; fi

}

jenkins_publish_iso()
{
  if [ ! -d "${SFTPFINALDIR}/iso/${TARGETREL}" ] ; then
    echo "Missing iso to push!"
    exit 1
  fi

  # Set the targets
  scale="pcbsd@pcbsd-master.scaleengine.net"
  target="/usr/home/pcbsd/mirror/iso"
  ssh ${scale} "mkdir -p ${target}/${TARGETREL}/${ARCH}" >/dev/null 2>/dev/null

  # Copy the ISOs
  rsync -va --delete-delay --delay-updates -e 'ssh' ${SFTPFINALDIR}/iso/${TARGETREL}/${ARCH}/ ${scale}:${target}/${TARGETREL}/${ARCH}/
  if [ $? -ne 0 ] ; then exit_clean; fi
}

jenkins_vm()
{
  create_workdir

  pull_world
  pull_iso

  cd ${TBUILDDIR}
  if [ $? -ne 0 ] ; then exit_clean; fi

  make vm
  if [ $? -ne 0 ] ; then exit_clean; fi

  # Now lets sync the ISOs
  cd ${TBUILDDIR}/iso
  if [ $? -ne 0 ] ; then exit_clean; fi

  if [ -n "$SFTPHOST" ] ; then
    ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${ISOSTAGE}" >/dev/null 2>/dev/null
    rsync -va --delete -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${ISOSTAGE}
    if [ $? -ne 0 ] ; then exit_clean; fi
  fi

  cleanup_workdir

  exit 0
}

jenkins_freenas_push_docs()
{
  # Now lets upload the docs
  if [ -n "$SFTPHOST" ] ; then
    rm -rf /tmp/handbookpush 2>/dev/null
    mkdir -p /tmp/handbookpush

    # Get the docs from the staging server
    rsync -va --delete-delay --delay-updates -e 'ssh' ${SFTPUSER}@${SFTPHOST}:${DOCSTAGE}/handbook/ /tmp/handbookpush
    if [ $? -ne 0 ] ; then exit_clean; fi

    cd /tmp/handbookpush
    if [ $? -ne 0 ] ; then exit_clean ; fi

    # Make them live!
    rsync -a -v -z --delete --exclude "truenas*" -e 'ssh -i /root/.ssh/id_dsa.jenkins' . jenkins@api.freenas.org:/tank/doc/userguide/html
    if [ $? -ne 0 ] ; then exit_clean; fi
    rm -rf /tmp/handbookpush 2>/dev/null
  fi

  return 0
}

jenkins_freenas_push_api()
{
  # Now lets upload the docs
  if [ -n "$SFTPHOST" ] ; then
    rm -rf /tmp/apipush 2>/dev/null
    mkdir -p /tmp/apipush

    # Get the docs from the staging server
    rsync -va --delete-delay --delay-updates -e 'ssh' ${SFTPUSER}@${SFTPHOST}:${DOCSTAGE}/api/ /tmp/apipush
    if [ $? -ne 0 ] ; then exit_clean; fi

    cd /tmp/apipush
    if [ $? -ne 0 ] ; then exit_clean ; fi

    # Make them live!
    rsync -a -v -z --delete --exclude "truenas*" -e 'ssh -i /root/.ssh/id_dsa.jenkins' . jenkins@api.freenas.org:/tank/api/html
    if [ $? -ne 0 ] ; then exit_clean; fi

    rm -rf /tmp/apipush 2>/dev/null
  fi

  return 0
}

jenkins_freenas_push()
{
  # Sanity check that the build was done on this node
  if [ ! -d "${FNASBDIR}" ] ; then
    echo "ERROR: No such build dir: ${FNASBDIR}"
    exit 1
  fi

  cd ${FNASBDIR}
  if [ $? -ne 0 ] ; then exit_clean ; fi

  git reset --hard
  git pull

  PROFILEARGS="$BUILDOPTS"

  if [ -z "$JENKINSVERSION" ] ; then
    echo "ERROR: Missing JENKINSVERSION="
  fi
  PROFILEARGS="${PROFILEARGS} VERSION=$JENKINSVERSION"

  if [ -n "$JENKINSINTUPDATE" -a "$JENKINSINTUPDATE" = "true" ] ; then
    PROFILEARGS="${PROFILEARGS} INTERNAL_UPDATE=yes"
  else
    if [ -z "$RELENG_PASSWORD" ] ; then
      echo "ERROR: Pushing public with no password set!"
      exit 1
    fi
  fi

  if [ -n "$RELENG_PASSWORD" ] ; then
    # Set the correct variable release-push expects
    IX_KEY_PASSWORD="${RELENG_PASSWORD}"
    export IX_KEY_PASSWORD
  fi

  # Push the release to download.freenas.org
  echo "make release-push ${PROFILEARGS}"
  make release-push ${PROFILEARGS}
  if [ $? -ne 0 ] ; then exit_clean ; fi

  return 0
}

jenkins_freenas_push_nightly()
{
  # Sanity check that the build was done on this node
  if [ ! -d "${FNASBDIR}" ] ; then
    echo "ERROR: No such build dir: ${FNASBDIR}"
    exit 1
  fi

  cd ${FNASBDIR}
  if [ $? -ne 0 ] ; then exit_clean ; fi

  # Push the release to download.freenas.org
  make release-push ${BUILDOPTS}
  if [ $? -ne 0 ] ; then exit_clean ; fi

  return 0
}

jenkins_truenas_docs()
{
  if [ ! -d "/tmp/build" ] ; then
     mkdir /tmp/build
  fi

  DDIR=`mktemp -d /tmp/build/XXXX` 

  git clone --depth=1 https://github.com/freenas/freenas-docs ${DDIR}
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  cd ${DDIR}/userguide
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  make TAG=truenas html
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  # Now lets sync the docs
  if [ -n "$SFTPHOST" ] ; then
    cd ${DDIR}/userguide/processed/_build/html/
    if [ $? -ne 0 ] ; then exit_clean ; fi

    ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${DOCSTAGE}/handbook" >/dev/null 2>/dev/null
    rsync -va --delete -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${DOCSTAGE}/tn-handbook
    if [ $? -ne 0 ] ; then exit_clean; fi
  fi

  rm -rf ${DDIR}

  return 0
}


jenkins_freenas_docs()
{
  if [ ! -d "/tmp/build" ] ; then
     mkdir /tmp/build
  fi

  DDIR=`mktemp -d /tmp/build/XXXX` 

  git clone --depth=1 https://github.com/freenas/freenas-docs ${DDIR}
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  cd ${DDIR}/userguide
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  make TAG=freenas html
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  # Now lets sync the docs
  if [ -n "$SFTPHOST" ] ; then
    cd ${DDIR}/userguide/processed/_build/html/
    if [ $? -ne 0 ] ; then exit_clean ; fi

    ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${DOCSTAGE}/handbook" >/dev/null 2>/dev/null
    rsync -va --delete -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${DOCSTAGE}/handbook
    if [ $? -ne 0 ] ; then exit_clean; fi
  fi

  rm -rf ${DDIR}

  return 0
}

jenkins_freenas_api()
{
  if [ ! -d "/tmp/build" ] ; then
     mkdir /tmp/build
  fi

  DDIR=`mktemp -d /tmp/build/XXXX` 

  git clone --depth=1 https://github.com/freenas/freenas ${DDIR}
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  cd ${DDIR}/docs/api
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  make html
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  # Now lets sync the api docs
  if [ -n "$SFTPHOST" ] ; then
    cd ${DDIR}/docs/api/_build/html/
    if [ $? -ne 0 ] ; then exit_clean ; fi

    ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${DOCSTAGE}/api" >/dev/null 2>/dev/null
    rsync -va --delete -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${DOCSTAGE}/api
    if [ $? -ne 0 ] ; then exit_clean; fi
  fi

  cleanup_workdir

  return 0
}

jenkins_trueos_docs()
{
  if [ ! -d "/tmp/build" ] ; then
     mkdir /tmp/build
  fi

  DDIR=`mktemp -d /tmp/build/XXXX` 

  git clone --depth=1 https://github.com/trueos/trueos-docs ${DDIR}
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  cd ${DDIR}/trueos-handbook
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  make html
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  # Now lets sync the TrueOS docs
  if [ -n "$SFTPHOST" ] ; then
    cd ${DDIR}/trueos-handbook/_build/html/
    if [ $? -ne 0 ] ; then exit_clean ; fi

    ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${DOCSTAGE}/trueos-docs" >/dev/null 2>/dev/null
    rsync -va --delete -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${DOCSTAGE}/trueos-docs
    if [ $? -ne 0 ] ; then exit_clean; fi
  fi

  cleanup_workdir
  return 0
}

jenkins_trueos_push_docs()
{
  cd /outgoing/doc/master/trueos-docs
  if [ $? -ne 0 ] ; then exit_clean ; fi

  rsync -va --delete-delay --delay-updates -e 'ssh' . docpush@web.pcbsd.org:/home/pcbsd/www/trueos.org/handbook/
  return 0
}


jenkins_trueos_lumina_docs()
{
  if [ ! -d "/tmp/build" ] ; then
     mkdir /tmp/build
  fi

  DDIR=`mktemp -d /tmp/build/XXXX` 

  git clone --depth=1 https://github.com/trueos/lumina-docs ${DDIR}
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  cd ${DDIR}
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  make html
  if [ $? -ne 0 ] ; then rm -rf ${DDIR} ; exit 1 ; fi

  # Now lets sync the Lumina docs
  if [ -n "$SFTPHOST" ] ; then
    cd ${DDIR}/_build/html/
    if [ $? -ne 0 ] ; then exit_clean ; fi

    ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${DOCSTAGE}/lumina-docs" >/dev/null 2>/dev/null
    rsync -va --delete -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${DOCSTAGE}/lumina-docs
    if [ $? -ne 0 ] ; then exit_clean; fi
  fi

  cleanup_workdir
  return 0
}

jenkins_trueos_push_lumina_docs()
{
  cd /outgoing/doc/master/lumina-docs
  if [ $? -ne 0 ] ; then exit_clean ; fi

  rsync -va --delete-delay --delay-updates -e 'ssh' . docpush@web.pcbsd.org:/home/pcbsd/www/lumina-desktop.org/handbook/
  return 0
}


jenkins_freenas()
{
  create_workdir

  # If we have a saved build state, lets pull that before we begin
  #jenkins_pull_fn_statedir

  # Check if this is a Release Engineer build
  echo ${BUILDTAG} | grep -q "releng"
  if [ $? -eq 0 ] ; then RELENGBUILD="YES" ; fi

  cd ${TBUILDDIR}
  if [ $? -ne 0 ] ; then exit_clean; fi

  make iso
  if [ $? -ne 0 ] ; then exit_clean; fi

  # Push the entire build statedir
  #jenkins_push_fn_statedir

  # Now lets sync the ISOs
  if [ -n "$SFTPHOST" ] ; then
    if [ "$FREENASLEGACY" = "YES" ] ; then
      cd ${FNASBDIR}/objs
      if [ $? -ne 0 ] ; then exit_clean ; fi
      rm -rf os-base
    else
      cd ${FNASBDIR}/_BE/release/
      if [ $? -ne 0 ] ; then exit_clean ; fi
    fi

    if [ -n "${RELENGBUILD}" ] ; then
      # Release Engineer Build
      # Don't cleanup all the old versions
      RSYNCFLAGS=""
      if [ $? -ne 0 ] ; then exit_clean; fi
    else
      RSYNCFLAGS="--delete"
    fi

    # Sync the ISO / Update files now
    ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${ISOSTAGE}" >/dev/null 2>/dev/null
    rsync -va ${RSYNCFLAGS} -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${ISOSTAGE}
    if [ $? -ne 0 ] ; then exit_clean; fi

    # Sync the releng build_env
    if [ -n "${RELENGBUILD}" ] ; then
      echo "$BUILD" | grep -q "truenas"
      if [ $? -eq 0 ] ; then
        envdir="/builds/TrueNAS/build_env"
      else
        envdir="/builds/FreeNAS/build_env"
      fi
      if [ ! -d "$envdir" ] ; then
        echo "WARNING: Unable to sync $envdir"
        cleanup_workdir
        return 0
      fi
      cd ${envdir}
      ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${ENVSTAGE}" >/dev/null 2>/dev/null
      rsync -va ${RSYNCFLAGS} -e 'ssh' . ${SFTPUSER}@${SFTPHOST}:${ENVSTAGE}
    fi

  fi

  cleanup_workdir

  return 0
}

jenkins_freenas_live_upgrade()
{
  create_workdir

  if [ -z "$LIVEHOST" ] ; then echo "Missing LIVEHOST!" ; exit_clean ; fi
  if [ -z "$LIVEUSER" ] ; then echo "Missing LIVEUSER!" ; exit_clean ; fi
  if [ -z "$LIVEPASS" ] ; then echo "Missing LIVEPASS!" ; exit_clean ; fi

  cd ${TBUILDDIR}
  make liveupgrade
  if [ $? -ne 0 ] ; then exit_clean ; fi

  cleanup_workdir

  return 0
}

jenkins_freenas_live_tests()
{
  create_workdir

  if [ -z "$LIVEHOST" ] ; then echo "Missing LIVEHOST!" ; exit_clean ; fi
  if [ -z "$LIVEUSER" ] ; then echo "Missing LIVEUSER!" ; exit_clean ; fi
  if [ -z "$LIVEPASS" ] ; then echo "Missing LIVEPASS!" ; exit_clean ; fi

  cd ${TBUILDDIR}
  make livetests
  if [ $? -ne 0 ] ; then exit_clean ; fi

  cleanup_workdir

  return 0
}


jenkins_freenas_tests()
{
  create_workdir

  cd ${TBUILDDIR}
  if [ $? -ne 0 ] ; then exit_clean ; fi

  if [ -n "$SFTPHOST" ] ; then
    # Now lets sync the ISOs
    if [ -d "${FNASBDIR}/_BE/release" ] ; then
      rm -rf ${FNASBDIR}/_BE/release
    fi

    mkdir -p ${FNASBDIR}/_BE/release
    cd ${FNASBDIR}/_BE/release
    if [ $? -ne 0 ] ; then exit_clean; fi

    ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${ISOSTAGE}" >/dev/null 2>/dev/null
    rsync -va --delete -e 'ssh' ${SFTPUSER}@${SFTPHOST}:${ISOSTAGE} ${FNASBDIR}/_BE/release/
    if [ $? -ne 0 ] ; then exit_clean ; fi
  fi

  cd ${TBUILDDIR}
  make tests
  if [ $? -ne 0 ] ; then exit_clean ; fi

  cleanup_workdir

  return 0
}

jenkins_push_fn_statedir()
{
  if [ -z "$SFTPHOST" ] ; then return 0 ; fi

  # Now lets push the new state dir
  if [ ! -d "${FNASBDIR}" ] ; then return 0 ; fi

  # Now rsync this sucker
  echo "Copying build-state to remote... ${FNASBDIR}/ -> ${FNSTATEDIR}/"
  rsync -a --delete -e 'ssh' ${FNASBDIR}/ ${SFTPUSER}@${SFTPHOST}:${FNSTATEDIR}/
  if [ $? -ne 0 ] ; then exit_clean ; fi
}

jenkins_pull_fn_statedir()
{
  if [ -z "$SFTPHOST" ] ; then return 0 ; fi

  # Make sure the remote dir exists
  ssh ${SFTPUSER}@${SFTPHOST} ls ${FNSTATEDIR}/ >/dev/null 2>/dev/null
  if [ $? -ne 0 ] ; then return 0 ; fi

  # Now lets cleanup old state dir
  if [ -d "${FNASBDIR}" ] ; then 
    echo "Removing local state dir..."
    rm -rf ${FNASBDIR} 2>/dev/null
    chflags -R noschg ${FNASBDIR} 2>/dev/null
    rm -rf ${FNASBDIR}
  fi
  mkdir -p ${FNASBDIR}

  # Now rsync this sucker
  echo "Copying build-state from remote... ${FNSTATEDIR}/ -> ${FNASBDIR}/"
  rsync -a --delete -e 'ssh' ${SFTPUSER}@${SFTPHOST}:${FNSTATEDIR}/ ${FNASBDIR}/
  if [ $? -ne 0 ] ; then exit_clean ; fi

  # Make sure to set proper ownership
  chown -R root:wheel ${FNASBDIR}
}

jenkins_ports_tests()
{
  echo "Changing to $WORKSPACE"
  cd "$WORKSPACE"
  if [ $? -ne 0 ] ; then exit 1 ; fi

  ./mkports.sh /usr/ports
  if [ $? -ne 0 ] ; then exit 1 ; fi

  # Now determine the port to build
  bPort=`cat mkport.sh | grep ^port= | cut -d '"' -f 2`
  cd /usr/ports/${bPort}
  if [ $? -ne 0 ] ; then exit 1; fi

  make clean
  if [ $? -ne 0 ] ; then exit 1; fi

  portlint
  if [ $? -ne 0 ] ; then exit 1; fi

  make BATCH=yes
  if [ $? -ne 0 ] ; then exit 1 ; fi

  make stage
  if [ $? -ne 0 ] ; then exit 1 ; fi

  make check-plist
  if [ $? -ne 0 ] ; then exit 1 ; fi

  exit 0
}

jenkins_mkcustard()
{
  cd /root

  # Roll back to clean snapshot
  VBoxManage snapshot custard restore clean
  if [ $? -ne 0 ] ; then
    echo "Failed to roll-back to @clean snapshot"
    exit 1
  fi

  # Start the custard VM and wait for it to finish
  ( VBoxHeadless -s custard >/dev/null 2>/dev/null ) &
  count=0

  echo "Waiting for Custard prep to finish..."
  while :
  do
    sleep 20
    echo "."

    vboxmanage list runningvms | grep -q "custard"
    if [ $? -ne 0 ] ; then
      break
    fi

    count=`expr $count + 1`
    if [ $count -gt 20 ] ; then
      VBoxManage controlvm custard poweroff
      exit 1
    fi
  done

  rm -rf /root/custard/
  mkdir /root/custard
  OUTFILE=/root/custard/custard-`date '+%Y-%m-%d-%H-%M'`.ova

  # Looks like custard finished on its own, lets package it up
  echo "Exporting CUSTARD .ova file..."
  VBoxManage modifyvm custard --nic1 bridged
  VBoxManage modifyvm custard --nic2 bridged
  VBoxManage export custard -o ${OUTFILE}
  chmod 644 ${OUTFILE}

  # Save the .ova to stage server
  if [ -n "$SFTPHOST" ] ; then
    STAGE="${SFTPFINALDIR}/iso/custard/amd64"

    echo "Moving CUSTARD to stage server..."
    ssh ${SFTPUSER}@${SFTPHOST} "mkdir -p ${STAGE}" >/dev/null 2>/dev/null
    rsync -va --delete -e 'ssh' /root/custard/ ${SFTPUSER}@${SFTPHOST}:${STAGE}/
    if [ $? -ne 0 ] ; then exit_clean ; fi
  fi

  exit 0
}

do_build_env_setup()
{

  # Set location of local PC-BSD build data
  PCBSDBDIR="/pcbsd"
  export PCBSDBDIR

  # Set the build tag
  BUILDTAG="$BUILD"
  export BUILDTAG

  # Set location of local FreeNAS build data
  FNASBDIR="/$BUILDTAG"
  export FNASBDIR

  if [ -z "$BUILD" ] ; then
    echo "Missing BUILD"
    exit_clean
  fi

  if [ ! -d "${BDIR}/${BUILD}" ] ; then
    echo "Invalid BUILD dir: $BUILD"
    exit_clean
  fi

  # Source build conf and set some vars
  cd ${BDIR}/${BUILD}

  echo "$TYPE" | grep -q "freenas"
  if [ $? -eq 0 ] ; then
    BRANCH="production"
    . freenas.cfg
  else
    if [ -z "$BRANCH" ] ; then
      BRANCH="production"
    fi
    if [ -e 'trueos.cfg' ] ; then
      . trueos.cfg
    else
      . pcbsd.cfg
    fi
  fi

  # Set the variables to reference poudrire jail locations
  if [ -z "$JAILVER" ] ; then
    JAILVER="$TARGETREL"
  fi
  case $TYPE in
    jail|pkg) WORLDTREL="$JAILVER" ;;
     *) WORLDTREL="$TARGETREL" ;;
  esac
  if [ -z "$PKGVERUPLOAD" ] ; then
    PKGVERUPLOAD="$WORLDTREL"
  fi

  # Poudriere variables
  if [ "$ARCH" = "i386" ] ; then PBUILD="${PBUILD}-i386"; fi
  PJAILNAME="`echo $JAILVER | sed 's|\.||g'`"
  echo "$TYPE" | grep -q trueos
  if [ $? -eq 0 ] ; then
    PBUILD="trueos-`echo $JAILVER | sed 's|\.||g'`"
    PPKGDIR="/poud/data/packages/${PJAILNAME}-trueosports"
    PJPORTSDIR="/poud/ports/trueosports"
  else
    PBUILD="pcbsd-`echo $JAILVER | sed 's|\.||g'`"
    PPKGDIR="/poud/data/packages/${PJAILNAME}-pcbsdports"
    PJPORTSDIR="/poud/ports/pcbsdports"
  fi
  export PBUILD PJPORTSDIR PPKGDIR

  # Set the remote directory for FreeNAS Builds state
  FNSTATEDIR="${SFTPWORKDIR}/fnstate/${TARGETREL}"
  ENVSTAGE="${SFTPFINALDIR}/iso/${TARGETREL}/build_env"

  # Set all the stage / work dirs
  if [ "$BRANCH" = "PRODUCTION" -o "$BRANCH" = "production" ] ; then
    PKGSTAGE="${SFTPFINALDIR}/pkg/${PKGVERUPLOAD}/amd64"
    ISOSTAGE="${SFTPFINALDIR}/iso/${TARGETREL}/amd64"
    DOCSTAGE="${SFTPFINALDIR}/doc/${TARGETREL}"
    WORKPKG="${SFTPWORKDIR}/pkg/${PKGVERUPLOAD}/amd64"
    WORKWORLD="${SFTPWORKDIR}/world/${WORLDTREL}/amd64"
  elif [ "$BRANCH" = "EDGE" -o "$BRANCH" = "edge" ] ; then
    PKGSTAGE="${SFTPFINALDIR}/pkg/${PKGVERUPLOAD}/edge/amd64"
    ISOSTAGE="${SFTPFINALDIR}/iso/${TARGETREL}/edge/amd64"
    DOCSTAGE="${SFTPFINALDIR}/doc/${TARGETREL}/edge"
    WORKPKG="${SFTPWORKDIR}/pkg/${PKGVERUPLOAD}/edge/amd64"
    WORKWORLD="${SFTPWORKDIR}/world/${WORLDTREL}/amd64"
  elif [ "$BRANCH" = "ENTERPRISE" -o "$BRANCH" = "enterprise" ] ; then
    PKGSTAGE="${SFTPFINALDIR}/pkg/${PKGVERUPLOAD}/enterprise/amd64"
    ISOSTAGE="${SFTPFINALDIR}/iso/${TARGETREL}/enterprise/amd64"
    DOCSTAGE="${SFTPFINALDIR}/doc/${TARGETREL}/enterprise"
    WORKPKG="${SFTPWORKDIR}/pkg/${PKGVERUPLOAD}/enterprise/amd64"
    WORKWORLD="${SFTPWORKDIR}/world/${WORLDTREL}/amd64"
  else
    echo "Invalid BRANCH"
    exit_clean
  fi
}

# Set the builds directory
BDIR="./builds"
export BDIR

# Check the type of build being done
case $TYPE in
  port-tests) ;;
  mkcustard) ;;
  *) do_build_env_setup ;;
esac
