#
#   Copyright (C) 2014 Cloudwatt <libre.licensing@cloudwatt.com>
#   Copyright (C) 2014 Nine Internet Solutions AG
#
#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
#
# Author: Loic Dachary <loic@dachary.org>
# Author: David Gurtner <aldavud@crimson.ch>
#
# == Define: ceph::osd
#
# Install and configure a ceph OSD
#
# === Parameters:
#
# [*title*] The OSD data path.
#   Mandatory. A path in which the OSD data is to be stored.
#
# [*ensure*] Installs ( present ) or remove ( absent ) an OSD
#   Optional. Defaults to present.
#   If set to absent, it will stop the OSD service and remove
#   the associated data directory.
#
# [*journal*] The OSD journal path.
#   Optional. Defaults to co-locating the journal with the data
#   defined by *title*.
#
# [*cluster*] The ceph cluster
#   Optional. Same default as ceph.
#
# [*exec_timeout*] The default exec resource timeout, in seconds
#   Optional. Defaults to $::ceph::params::exec_timeout
#
define ceph::osd (
  $ensure = present,
  $journal = undef,
  $cluster = undef,
  $exec_timeout = $::ceph::params::exec_timeout,
  ) {

    $data = $name

    if $cluster {
      $cluster_option = "--cluster ${cluster}"
      $cluster_name = $cluster
    } else {
      $cluster_name = 'ceph'
    }

    if $journal {
       $journal_drive = $journal
    } else {
       $journal_drive = "${data}1"
    }
    if $ensure == present {

      $ceph_prepare = "ceph-osd-prepare-${name}"
      $ceph_activate = "ceph-osd-activate-${name}"

      Ceph_Config<||> -> Exec[$ceph_prepare]
      Ceph::Mon<||> -> Exec[$ceph_prepare]
      Ceph::Key<||> -> Exec[$ceph_prepare]
      # ceph-disk: prepare should be idempotent http://tracker.ceph.com/issues/7475
      exec { $ceph_prepare:
        command   => "/bin/true # comment to satisfy puppet syntax requirements
set -ex
if ! test -b ${data} ; then
  mkdir -p ${data}
fi
ceph-disk prepare --zap-disk ${cluster_option} ${data} ${journal}
",
        unless    => "/bin/true # comment to satisfy puppet syntax requirements
set -ex
ceph-disk list | grep -E ' *${data}1? .*ceph data, (prepared|active)' ||
ls -l /var/lib/ceph/osd/${cluster_name}-* | grep ' ${data}\$'
",
        logoutput => true,
        timeout   => $exec_timeout,
      }

      Exec[$ceph_prepare] -> Exec[$ceph_activate]
      exec { $ceph_activate:
        command   => "/bin/true # comment to satisfy puppet syntax requirements
set -ex
if ! test -b ${data} ; then
  mkdir -p ${data}
fi
# activate happens via udev when using the entire device
#if ! test -b ${data} || ! test -b ${data}1 ; then
  ceph-disk activate ${journal_drive} || true
#fi
",
        unless    => "/bin/true # comment to satisfy puppet syntax requirements
set -ex
ceph-disk list | grep -E ' *${data}1? .*ceph data, active'", # ||
#ls -ld /var/lib/ceph/osd/${cluster_name}-* | grep ' ${data}\$'
#",
        logoutput => true,
      }

    } else {

      # ceph-disk: support osd removal http://tracker.ceph.com/issues/7454
      exec { "remove-osd-${name}":
        command   => "/bin/true # comment to satisfy puppet syntax requirements
set -ex
if [ -z \"\$id\" ] ; then
  id=\$(ceph-disk list | sed -nEe 's:^ *${data}1? .*(ceph data|mounted on).*osd\\.([0-9]+).*:\\2:p')
fi
if [ -z \"\$id\" ] ; then
  id=\$(ls -ld /var/lib/ceph/osd/${cluster_name}-* | sed -nEe 's:.*/${cluster_name}-([0-9]+) *-> *${data}\$:\\1:p' || true)
fi
if [ \"\$id\" ] ; then
  stop ceph-osd cluster=${cluster_name} id=\$id || true
  service ceph stop osd.\$id || true
  ceph ${cluster_option} osd rm \$id
  ceph auth del osd.\$id
  rm -fr /var/lib/ceph/osd/${cluster_name}-\$id/*
  umount /var/lib/ceph/osd/${cluster_name}-\$id || true
  rm -fr /var/lib/ceph/osd/${cluster_name}-\$id
fi
",
        unless    => "/bin/true # comment to satisfy puppet syntax requirements
set -ex
if [ -z \"\$id\" ] ; then
  id=\$(ceph-disk list | sed -nEe 's:^ *${data}1? .*(ceph data|mounted on).*osd\\.([0-9]+).*:\\2:p')
fi
if [ -z \"\$id\" ] ; then
  id=\$(ls -ld /var/lib/ceph/osd/${cluster_name}-* | sed -nEe 's:.*/${cluster_name}-([0-9]+) *-> *${data}\$:\\1:p' || true)
fi
if [ \"\$id\" ] ; then
  test ! -d /var/lib/ceph/osd/${cluster_name}-\$id
else
  true # if there is no id  we do nothing
fi
",
        logoutput => true,
        timeout   => $exec_timeout,
      } -> Ceph::Mon<| ensure == absent |>
    }

}
