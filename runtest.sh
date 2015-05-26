#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# vim: autoindent tabstop=2 shiftwidth=2 expandtab softtabstop=2 filetype=sh
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /spice/setup-autotest
#   Description: Prepare autotest environment
#   Author: Andrei Stepanov <astepano@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2015 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

BEAKERLIB_DIR="$(pwd)/journal/journal-$(date '+%F-%H-%M-%S')"
declare -rx BEAKERLIB_DIR

rlJournalStart

TEST="Spice QE: setup autotest env"
# Test name
readonly TEST="/spice/setup-autotest"

# Script input parameters
readonly IN_PACKAGES=${IN_PACKAGES:-}

# Nic shared with KVM instances
readonly IN_NIC=${IN_NIC:-eth1}

# Bridge used to connect KVM instances
readonly IN_BRIDGE=${IN_BRIDGE:-virbr0}

# Autotest git repo
readonly IN_AUTOTEST_REPO="${IN_AUTOTEST_REPO:-git://github.com/spiceqa/autotest.git}"

# Spice virt-test
# VIRT_REMOTE" value="git://github.com/spiceqa/virt-test.git"/>
readonly IN_VIRT_REPO="${IN_VIRT_REPO:-git://github.com/spiceqa/virt-test.git}"

# VIRT_BRANCH" value="latest"/>
readonly IN_BRANCH_VIRT_TEST="${IN_BRANCH_VIRT_TEST:-latest}"
readonly IN_BRANCH_AUTOTEST="${IN_BRANCH_AUTOTEST:-master}"
readonly IN_DIR_VIRT_TEST="${IN_DIR_VIRT_TEST:-virt-test}"
readonly IN_DIR_AUTOTEST="${IN_DIR_AUTOTEST:-autotest}"

AUTOTEST_PATH="$(pwd)/$IN_DIR_AUTOTEST"
declare -xr AUTOTEST_PATH

readonly IN_CLIENT_OS="${IN_CLIENT_OS:-RHEL6-x64-latest}"
readonly IN_GUEST_OS="${IN_GUEST_OS:-RHEL6-x64-latest}"

# Additional tests filter passed through env
readonly IN_FILTER_TESTS="${IN_FILTER_TESTS:-}"

readonly IN_REPO_BASE="${IN_REPO_BASE:-http://download.englab.brq.redhat.com/pub/rhel/rel-eng/}"
readonly IN_RHEL7_x64_URL="${IN_RHEL7_x64_URL:-$IN_REPO_BASE/latest-RHEL-7/compose/Workstation/x86_64/os/}"
readonly IN_RHEL6_x64_URL="${IN_RHEL6_x64_URL:-$IN_REPO_BASE/latest-RHEL-6/compose/Workstation/x86_64/os/}"
readonly IN_RHEL6_x86_URL="${IN_RHEL6_x86_URL:-$IN_REPO_BASE/latest-RHEL-6/compose/Workstation/i386/os/}"

readonly TESTS_CFG="$IN_DIR_VIRT_TEST/qemu/cfg/tests-spice.cfg"
readonly INST_CFG="$IN_DIR_VIRT_TEST/qemu/cfg/spice-vm-install.cfg"
readonly COMMON_CFG="$IN_DIR_VIRT_TEST/qemu/cfg/spice-common.cfg"

readonly INST_TESTS="$BEAKERLIB_DIR/install-list.txt"
readonly INST_DICS="$BEAKERLIB_DIR/install-dics.txt"
readonly INST_RUN="$BEAKERLIB_DIR/install-run.txt"

readonly RUN_TESTS="$BEAKERLIB_DIR/tests-list.txt"
readonly RUN_DICS="$BEAKERLIB_DIR/tests-dics.txt"
readonly RUN_RUN="$BEAKERLIB_DIR/tests-run.txt"

readonly IN_PROXY_IP="${IN_PROXY_IP:-}"

# Packages to install
readonly PACKAGES="
dnsmasq
genisoimage
python-imaging
gdb
boost-devel
glibc-devel
libvirt
python-devel
ntpdate
gstreamer-plugins-good
gstreamer-python
tcpdump
squid
p7zip
"

###################
# BEAKER LIB PHASES
###################

phase_epel() {

  #
  # Phase: add epel
  #

  rlPhaseStart "FAIL" "$TEST: Add EPEL repository"

  rlRun "rlImport 'distribution/epel'" || rlDie "Can't setup EPEL repo"
  rlRun "yum-config-manager --enable epel" || rlDie "Can't enable EPEL repo"

  rlPhaseEnd
}


phase_http_logs() {

  #
  # Phase: add epel
  #

  rlPhaseStart "FAIL" "$TEST: Add EPEL repository"


  rlRun "rlImport usability/nginx-custom-dir" || rlDie "Can't HTTP export logs"
  ndirAdd "/journal" "$(pwd)" || rlDie "Can't provide logs"
  ndirAdd "/logs" "$(pwd)/$IN_DIR_VIRT_TEST" || rlDie "Can't provide logs"

  rlPhaseEnd
}


phase_pkgs_inst() {

  #
  # Phase: install packages
  #

  rlPhaseStart "FAIL" "$TEST: Install packages"

  readarray PKGS1 <<< "$PACKAGES"
  readarray PKGS2 <<< "$IN_PACKAGES"

  # Remove empty elements
  PKGS=(${PKGS1[@]} ${PKGS2[@]})

  for p in "${PKGS[@]}"; do
    if ! rlRun "rlCheckRpm $p"; then
      yum -y install "$p"
      rlRun "yum -y install $p"
      if (($? > 0)); then
        rlDie "Can't install $p"
      fi
    fi
  done

  rlPhaseEnd
}


phase_net_cfg() {

  #
  # Phase: Network setup
  #

  rlPhaseStart "FAIL" "$TEST: Network setup"

  # Stop firewalld
  if rlCheckRpm "firewalld"; then
    if rlRun "firewall-cmd --state"; then
      rlRun "rlServiceStop firewalld"
    fi
  fi

  # Stop iptables service for RHEL6
  if rlIsRHEL ">=6"; then
    rlRun "rlServiceStop iptables"
  fi

  # Network notes
  # * Interfaces should have name: ethX
  # * Interfaces are configured at /etc/sysconfig/network-scripts/ifcfg-ethX
  # * eth0 is kept as is. Connection to the host running tests.
  # * eth1 - must exists. Altered.
  #
  # +-----+-----+---------+-----+------+------+----------------+
  # | you | <-> | network | <-> | eth0 | HOST | eth1(DMZ DHCP) |
  # +-----+-----+---------+-----+------+------+----------------+
  # |                                         |       ||       |
  # +                                         +----------------+
  # |                                         |     virbr0     |
  # +                                         +----------------+
  # |                                         | tap1 |  | tap2 |
  # +                                         +------+--+------+
  # |                                         |  vm1 |  |  vm2 |
  # +-----------------------------------------+------+--+------+
  # http://www.tablesgenerator.com

  rlRun "ip link show $IN_NIC >/dev/null 2>&1" || rlDie "$IN_NIC must exists"

  readonly net_base="/etc/sysconfig/network-scripts/"
  readonly icfg="$net_base/ifcfg-$IN_NIC"
  readonly bcfg="$net_base/ifcfg-$IN_BRIDGE"

  # Already configured ?
  if ! bridge link show dev "$IN_NIC" | grep -s "$IN_BRIDGE"; then

    [ -e "$ifcg" ] && rlFileBackup "$icfg"
    [ -e "$bcfg" ] && rlFileBackup "$bcfg"

    # Create bridge iface
    if ! "ip link show $IN_BRIDGE >/dev/null 2>&1"; then
      cat <<-EOF > "$bcfg"
			# Created by $TEST
			DEVICE=$IN_BRIDGE
			BOOTPROTO=dhcp
			DEFROUTE=no
			TYPE=Bridge
			NM_CONTROLLED=no
			ONBOOT=yes
			EOF
    fi

    rlRun "ifdown $IN_NIC"

    sed -i -e '/NM_CONTROLLED/d' "$icfg"
    sed -i -e '/BOOTPROTO/d' "$icfg"
    sed -i -e '/ONBOOT/d' "$icfg"
    sed -i -e '/DEFROUTE/d' "$icfg"
    sed -i -e '/BRIDGE/d' "$icfg"

    echo 'NM_CONTROLLED=no' >> "$icfg"
    echo 'BOOTPROTO=no' >> "$icfg"
    echo 'ONBOOT=yes' >> "$icfg"
    echo 'DEFROUTE=no' >> "$icfg"
    echo "BRIDGE=${IN_BRIDGE}" >> "$icfg"

    rlRun -t -l "ifup $IN_NIC"
    rlRun -t -l "ifup $IN_BRIDGE"
  fi

  rlRun "ip link show $IN_BRIDGE >/dev/null 2>&1"
  if (($? > 0)); then
    rlDie "$IN_BRIDGE must exists."
  fi

  rlRun "bridge link show dev $IN_NIC | grep -s $IN_BRIDGE"
  if (($? > 0)); then
    rlDie "$IN_NIC belongs to bridge $IN_BRIDGE"
  fi

  rlPhaseEnd
}

phase_get_tests() {

  #
  # Phase: Get tests
  #

  rlPhaseStart "FAIL" "$TEST: Get tests"

  if ! [ -d "$IN_DIR_AUTOTEST" ]; then
    rlRun -t -l "git clone $IN_AUTOTEST_REPO $IN_DIR_AUTOTEST"
    if (($? > 0)); then
      rlDie "$IN_AUTOTEST_REPO cloned into $IN_DIR_AUTOTEST"
    fi
  fi

  pushd "$IN_DIR_AUTOTEST"
  rlRun "git checkout $IN_BRANCH_AUTOTEST" 0
  if (($? > 0)); then
    rlDie "Branch is $IN_BRANCH_AUTOTEST"
  fi
  popd

  if ! [ -d "$IN_DIR_VIRT_TEST" ]; then
    rlRun -t -l "git clone $IN_VIRT_REPO $IN_DIR_VIRT_TEST"
    if (($? > 0)); then
      rlDie "$IN_VIRT_REPO cloned into $IN_DIR_VIRT_TEST"
    fi
  fi

  pushd "$IN_DIR_VIRT_TEST"
  rlRun "git checkout $IN_BRANCH_VIRT_TEST"
  if (($? > 0)); then
    rlDie "Branch is $IN_BRANCH_VIRT_TEST" $?
  fi
  popd

  rlPhaseEnd
}


phase_cartesian_install_cfg() {

  #
  # Phase: Installation cartesian
  #

  rlPhaseStart "FAIL" "$TEST: Installation cartesian"

  local filter_cfg="$(pwd)/$INST_CFG-installation-filter"

  rlLogInfo "Update $INST_CFG file, with urls"
  sed -i '/RHEL6-x64-latest/,/only/ s| url =.*| url = '${IN_RHEL6_x64_URL}'|' "$INST_CFG"
  sed -i '/RHEL6-x86-latest/,/only/ s| url =.*| url = '${IN_RHEL6_x86_URL}'|' "$INST_CFG"
  sed -i '/RHEL7-x64-latest/,/only/ s| url =.*| url = '${IN_RHEL7_x64_URL}'|' "$INST_CFG"

  if [ -n "$CLIENT_URL" ]; then
    rlLogInfo "Update $INST_CFG file, with CLIENT_URL"
    sed -i '/'${IN_CLIENT_OS}'/,/only/ s| url=.*| url='${CLIENT_URL}'|' "$INST_CFG"
  fi

  if [ -n "$GUEST_URL" ]; then
    rlLogInfo "Update $INST_CFG file, with GUEST_URL"
    sed -i '/'${IN_GUEST_OS}'/,/only/ s| url=.*| url='${GUEST_URL}'|' "$INST_CFG"
  fi

  # Set filter for clients/guests.
  # Init filter
  INSTALL_FILTER="only"

  # RHEL is always installed from url, Windows from ISO

  if [[ $IN_CLIENT_OS == *"Win"* ]]
  then
    INSTALL_FILTER="${INSTALL_FILTER} cdrom"
  else
    INSTALL_FILTER="${INSTALL_FILTER} url"
  fi

  INSTALL_FILTER="${INSTALL_FILTER}.client.${IN_CLIENT_OS}"

  if [[ $IN_GUEST_OS == *"Win"* ]]
  then
    INSTALL_FILTER="${INSTALL_FILTER} cdrom"
  else
    INSTALL_FILTER="${INSTALL_FILTER} url"
  fi

  INSTALL_FILTER="${INSTALL_FILTER}.guest.${IN_GUEST_OS}"

  rlLogInfo "Filter is: $INSTALL_FILTER"

  echo "$INSTALL_FILTER" > "$filter_cfg"

  rlLogInfo "Include $filter_cfg into $INST_CFG"
  # Remove old filer
  sed -i -e '/include.*installation-filter/d' "$INST_CFG"
  # Add new filter
  sed -i -e "1iinclude $filter_cfg" "$INST_CFG"

  rlPhaseEnd
}


phase_cartesian_tests_cfg() {

  #
  # Phase: Tests cartesian config
  #

  rlPhaseStart "FAIL" "$TEST: Tests cartesian config"

  rlAssertExists "$TESTS_CFG" || rlDie "Can't find $tests_cfg"

  # Filter for this tests run
  readonly tests_cfg_filter="$(pwd)/$TESTS_CFG-run-filter"

  rlAssertExists "$COMMON_CFG" || rlDie "Can't find $COMMON_CFG"

  readonly TEST_DIR="$(pwd)/remote-viewer-gui-tests"

  #  Dogtail app's GUI tests
  sed -i "s|test_dir.*|test_dir = $TEST_DIR |" "$COMMON_CFG"

  if ! grep -q -s "audio_src" "$TESTS_CFG"; then
    sed -i '/rv_binary/a\audio_src' "$TESTS_CFG"
  fi
  sed -i "s|audio_src.*|audio_src=$(pwd)/tone.wav|" "$TESTS_CFG"

  echo "only Client-${IN_CLIENT_OS}.Guest-${IN_GUEST_OS}" > "$tests_cfg_filter"
  if [ -n "$IN_FILTER_TESTS" ]; then
    echo "only $IN_FILTER_TESTS" >> "$tests_cfg_filter"
  fi

  rlLogInfo "Include $tests_cfg_filter into $TESTS_CFG"
  # Remove old filer
  sed -i -e '/include.*-run-filter/d' "$TESTS_CFG"
  # Add new filter
  sed -i -e "1iinclude $tests_cfg_filter" "$TESTS_CFG"

  rlPhaseEnd
}



phase_squid_proxy() {

  #
  # Phase: squid proxy config
  #

  rlPhaseStart "FAIL" "$TEST: Config squid proxy"

  rlFileBackup "/etc/squid/squid.conf"
  cp -f "squid.conf" "/etc/squid/squid.conf"
  rlRun -t -l "rlServiceStart squid" || rlDie "Can't (re)start squid proxy"

  proxy_ip="$(ip a show dev "$IN_BRIDGE" | grep -m1 -o '[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+\.[[:digit:]]\+' | head -1)"
  proxy_ip=${IN_PROXY_IP:-$proxy_ip}

  if ! grep -q -s "spice_proxy" "$TESTS_CFG"; then
    sed -i '/rv_binary/a\spice_proxy' "$TESTS_CFG"
  fi
  sed -i "s/spice_proxy.*/spice_proxy=$proxy_ip/" "$TESTS_CFG"

  rlLogInfo "Update $TESTS_CFG with Squid proxy ip: $proxy_ip"

  rlPhaseEnd
}


phase_virt_test_bootstrap() {

  #
  # phase: virt-test bootstrap
  # run bootstrap script, look for a prompt to install jeos
  #

  rlPhaseStart "FAIL" "$TEST: virt-test bootstrap"

  if [ "$SPICE_VERSION" = "upstream" ]; then
    rlRun "yes n | ./$IN_DIR_VIRT_TEST/run -t qemu --bootstrap" || rlDie "Bootstrap fail"
  else
    rlRun "yes n | ./$IN_DIR_VIRT_TEST/qemu/get_started.py" || rlDie "Bootstrap fail"
  fi

  rlPhaseEnd
}


phase_install_vms() {

  #
  # phase: install VMs
  #

  rlPhaseStart "FAIL" "$TEST: install VMs"

  local ret=

  rlRun "./$IN_DIR_VIRT_TEST/virttest/cartesian_config.py $INST_CFG 2>&1 | tee $INST_TESTS"
  ret=$?
  rlFileSubmit "$INST_TESTS" "$(basename "$INST_TESTS")"
  if (($ret > 0)); then
    rlDie "Can't dump install tests"
  fi

  rlRun "./$IN_DIR_VIRT_TEST/virttest/cartesian_config.py -c $INST_CFG 2>&1 | tee $INST_DICS"
  ret=$?
  rlFileSubmit "$INST_DICS" "$(basename "$INST_DICS")"
  if (($ret > 0)); then
    rlDie "Can't dump install dics"
  fi

  # Ready, Steady, Go!
  rlRun "./$IN_DIR_VIRT_TEST/run -t qemu --no-downloads -v -c $INST_CFG 2>&1 | tee $INST_RUN "
  ret=$?
  rlFileSubmit "$INST_RUN" "$(basename "$INST_RUN")"
  if (($ret > 0)); then
    rlDie "Can't install VMs"
  fi

  rlPhaseEnd
}


phase_run_tests() {

  #
  # phase: Run tests
  #

  rlPhaseStart "FAIL" "$TEST: Run tests"

  local ret=

  rlRun "./$IN_DIR_VIRT_TEST/virttest/cartesian_config.py $TESTS_CFG 2>&1 | tee $RUN_TESTS"
  ret=$?
  rlFileSubmit "$RUN_TESTS" "$(basename "$RUN_TESTS")"
  if (($ret > 0)); then
    rlDie "Can't dump tests list"
  fi

  rlRun "./$IN_DIR_VIRT_TEST/virttest/cartesian_config.py -c $TESTS_CFG 2>&1 | tee $RUN_DICS"
  ret=$?
  rlFileSubmit "$RUN_DICS" "$(basename "$RUN_DICS")"
  if (($ret > 0)); then
    rlDie "Can't dump dics"
  fi

  # Ready, Steady, Go!
  rlRun "./$IN_DIR_VIRT_TEST/run -t qemu --no-downloads -v -c $TESTS_CFG 2>&1 | tee $RUN_RUN"
  rlFileSubmit "$RUN_RUN" "$(basename "$RUN_RUN")"

  rlPhaseEnd
}



#############
# ENTRY POINT
#############

#
# Beaker library initialization
#

# XXX
cp "video_sample_test.ogv" "../shared/deps/"


phase_http_logs
phase_epel
phase_pkgs_inst
phase_net_cfg
phase_get_tests

rlFileBackup "$TESTS_CFG"
rlFileBackup "$INST_CFG"
rlFileBackup "$COMMON_CFG"

phase_virt_test_bootstrap
phase_cartesian_install_cfg
phase_cartesian_tests_cfg
phase_squid_proxy
phase_install_vms
phase_run_tests

#
# Beaker library shutdown
#
rlJournalEnd
rlJournalPrintText --full-journal
