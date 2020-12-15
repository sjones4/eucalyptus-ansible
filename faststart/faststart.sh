#!/bin/bash

faststart_init()
{

OPTIND=1
LOGFILE="/var/log/euca-install-$(date +%m.%d.%Y-%H.%M.%S).log"

# Initialize our own variables:
eucalyptus_release="https://downloads.eucalyptus.cloud/software/eucalyptus/5/rhel/7/x86_64/eucalyptus-release-5-1.11.as.el7.noarch.rpm"
assume_yes=0
batch_mode=0

# Environment configuration, used with batch mode:
efs_ip_cidr="${efs_ip_cidr:-}"

# Derived or hard-coded values
efs_ip_range=""
efs_inventory="${efs_inventory:-/root/faststart_inventory.yml}"
efs_inventory_only="${efs_inventory_only:-no}"
efs_certbot_configure="${efs_certbot_configure:-no}"
efs_firewalld_configure="${efs_firewalld_configure:-yes}"
efs_skip_tags="${efs_skip_tags:-none}" # "none" does not match any tags

usage()
{
    echo "usage: faststart.sh [-y] [-r RELEASE_RPM_URL ] | [-h]"
}

while [ "$1" != "" ]; do
    case $1 in
        -r | --release-url )    shift
                                eucalyptus_release=$1
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        -y | --assumeyes )      assume_yes=1
                                ;;
        --batch )               batch_mode=1
                                assume_yes=1
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

} # end function faststart_init

# Function for all of faststart, ensures nothing is run until script is
# complete
faststart()
{

###############################################################################
# SECTION 0: FUNCTIONS AND CONSTANTS.
#
###############################################################################

# Hooray for the tea cup!
IMGS=(
"
   ( (     \n\
    ) )    \n\
  ........ \n\
  |      |]\n\
  \      / \n\
   ------  \n
" "
     ) )   \n\
    ( (    \n\
  ........ \n\
  |      |]\n\
  \      / \n\
   ------  \n
" )
IMG_REFRESH="3"
LINES_PER_IMG=$(( $(echo $IMGS[0] | sed 's/\\n/\n/g' | wc -l) + 1 ))

# Output loop for tea cup
tput_loop()
{
    for((x=0; x < LINES_PER_IMG; x++)); do tput "$1"; done;
}

# Let's have some tea!
tea()
{
    local pid=$1
    IFS='%'
    if [ ! -t 3 ] ; then
        while [ "$(ps ax | awk '{print $1}' | grep $pid)" ]; do
            sleep 15
        done
    else
        tput civis
        while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do for x in "${IMGS[@]}"; do
            echo -ne "$x"
            tput_loop "cuu1"
            sleep $IMG_REFRESH
        done; done
        tput_loop "cud1"
        tput cvvis
    fi
}>&3  # no tea for logs

# Check cidr input to ensure valid
valid_cidr()
{
    local  cidr=$1
    local  stat=1

    if [[ $cidr =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/2[4-8]$ ]]; then
        OIFS=$IFS
        IFS='.'
        ip=(${cidr%%/*})
        prefix="${cidr##*/}"
        IFS=$OIFS
        [[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
            && ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
        stat=$?

        # ensure valid for prefix
        addresses=$((2 ** (32-prefix)))
        ip_4=${ip[3]}
        if [ $(((ip_4 / addresses) * addresses)) -ne $ip_4 ] ; then
          stat=1
        fi
    fi
    return $stat
}

# Timer check for runtime of the installation
timer()
{
    if [[ $# -eq 0 ]]; then
        date '+%s'
    else
        local  stime=$1
        etime=$(date '+%s')

        if [[ -z "$stime" ]]; then stime=$etime; fi

        dt=$((etime - stime))
        ds=$((dt % 60))
        dm=$(((dt / 60) % 60))
        dh=$((dt / 3600))
        printf '%d:%02d:%02d' $dh $dm $ds
    fi
}

# Read a yes no input, assuming yes when applicable
readyesno()
{
    if [ $assume_yes -eq 1 ] ; then
        if [ -z "${!1:-}" ] ; then
            export $1="Y"
        fi
    else
        read "$1"
    fi
}

# Read input, guessing or using environment when applicable
readinput()
{
    if [ $batch_mode -eq 1 ] ; then
        if [ -z "${!1:-}" ] ; then
            export $1=""
        fi
    else
        read "$1"
    fi
}

inputerror() {
    echo "$1"
    if [ $batch_mode -eq 1 ] ; then
        echo "Install failed due to missing or invalid configuration"
        exit 1
    fi
}

###############################################################################
# SECTION 1: PRECHECK.
#
# Any immediately diagnosable condition that might prevent Euca from being
# properly installed should be checked here.
###############################################################################

echo "NOTE: if you're running on a laptop, you might want to make sure that"
echo "you have turned off sleep/ACPI in your BIOS.  If the laptop goes to sleep,"
echo "virtual machines could terminate."
echo ""

echo "Continue? [Y/n]"
readyesno continue_laptop
if [ "$continue_laptop" = "n" ] || [ "$continue_laptop" = "N" ]
then
    echo "Stopped by user request."
    exit 1
fi

# Invoke timer start.
t=$(timer)

echo ""

echo "[Precheck] Checking OS"
egrep 'release.*7.[56789]' "/etc/redhat-release" 1>&4 2>&4
if [ "$?" != "0" ]; then
    echo "======"
    echo "[FATAL] Operating system not supported"
    echo ""
    echo "Please note: Eucalyptus Faststart only runs on RHEL or CentOS 7.5+"
    echo ""
    echo ""
    exit 10
fi
echo "[Precheck] OK, OS is supported"
echo ""

echo "[Precheck] Checking root"
efs_user=$(whoami)
if [ "$efs_user" != 'root' ]; then
    echo "======"
    echo "[FATAL] Not running as root"
    echo ""
    echo "Please run Eucalyptus Faststart as the root user."
    exit 5
fi
echo "[Precheck] OK, running as root"
echo ""

echo "[Precheck] Checking available disk space"
DiskSpace=$(df -Pk /var | tail -1 | awk '{ print $4}')
if [ "$DiskSpace" -lt "100000000" ]; then
    echo "[WARNING] we recommend at least 100G of disk space available"
    echo "in /var for a Eucalyptus Faststart installation.  Running with"
    echo "less disk space may result in issues with image and volume"
    echo "management, and may dramatically reduce the number of instances"
    echo "your cloud can run simultaneously."
    echo ""
    echo "Your free space is: $(df -Ph /var | tail -1 | awk '{ print $4}')"
    echo ""
    echo "Continue? [y/N]"
    readyesno continue_disk
    if [ "$continue_disk" = "n" ] || [ "$continue_disk" = "N" ] || [ -z "$continue_disk" ]
    then
        echo "Stopped by user request."
        exit 1
    fi
fi
echo "[Precheck] OK, sufficient space for Eucalyptus"
echo ""

echo "[Precheck] Checking for installed Eucalyptus"
rpm -q eucalyptus &>/dev/null
if [ "$?" = "0" ]; then
    echo "====="
    echo "[WARNING] Eucalyptus already installed!"
    echo ""
    echo "An installation of Eucalyptus has been detected on this system. If you wish to"
    echo "reinstall Eucalyptus removing the previous installation first is recommended."
    echo ""
    echo "Continue? [y/N]"
    readyesno continue_reinstall
    if [ "$continue_reinstall" = "n" ] || [ "$continue_reinstall" = "N" ] || [ -z "$continue_reinstall" ]
    then
        echo "Stopped by user request."
        exit 1
    fi
fi
echo "[Precheck] OK, Eucalyptus not installed or will attempt to overwrite"
echo ""

echo "[Precheck] Checking for ansible inventory"
if [ -f "${efs_inventory}" ]; then
    echo "====="
    echo "[WARNING] Faststart ansible inventory will be overwritten!"
    echo ""
    echo "An existing ansible inventory file for Eucalyptus is present. This will"
    echo "be overwritten and any edits lost."
    echo ""
    echo "Continue? [y/N]"
    readyesno continue_reinstall
    if [ "$continue_reinstall" = "n" ] || [ "$continue_reinstall" = "N" ] || [ -z "$continue_reinstall" ]
    then
        echo "Stopped by user request."
        exit 1
    fi
fi
echo "[Precheck] OK, ansible inventory not present or will be overwritten"
echo ""

echo "[Precheck] Checking for network service"
systemctl is-active network.service 1>&4 2>&4
if [ "$?" != "0" ]; then
    echo "====="
    echo "WARNING: Network service is not active."
    echo ""
    echo "Do you want me to enable the network service?"
    echo ""
    echo "If you answer 'yes' I will change that for you."
    echo "Proceed? [y/N]"
    readyesno enable_network_service
    echo "$enable_network_service" | grep -qs '^[Yy]'
    if [ $? = 0 ]; then
        echo "I am changing that for you now."
        systemctl start network.service 1>&4 2>&4
        if [ "$?" != "0" ]; then
          echo "====="
          echo "[FATAL] Error starting network service"
          echo ""
          echo "Network service could not be started, check logs for details"
          echo "(journalctl -u network.service)."
          exit 12
        fi
        systemctl enable network.service 1>&4 2>&4
        echo "Done."
    else
        echo "Stopped by user request."
        exit 1
    fi
    echo ""
else
    echo "[Precheck] OK, network service is active"
    echo ""
fi

echo "[Precheck] Checking hardware virtualization"
egrep '^flags.*(vmx|svm)' /proc/cpuinfo &>/dev/null
if [ "$?" != "0" ]; then
    echo "====="
    echo "[FATAL] Processor doesn't support virtualization"
    echo ""
    echo "Your processor doesn't appear to support virtualization."
    echo "Eucalyptus requires virtualization to be enabled on your system."
    echo "Please check your BIOS settings, or install Eucalyptus on a"
    echo "system that supports virtualization."
    echo ""
    echo ""
    exit 20
fi
echo "[Precheck] OK, processor supports virtualization"
echo ""

echo "[Precheck] Checking if selinux enabled"
test -x /usr/sbin/selinuxenabled && /usr/sbin/selinuxenabled
if [ "$?" != "0" ]; then
    echo "====="
    echo "NOTICE: selinux is not enabled."
    echo ""
    echo "Do you want to continue without selinux support?"
    echo ""
    echo "Proceed? [y/N]"
    readyesno continue_without_selinux
    echo "$continue_without_selinux" | grep -qs '^[Yy]'
    if [ $? = 0 ]; then
        echo "Skipping selinux support for install."
        efs_skip_tags="${efs_skip_tags},selinux"
    else
        echo "Stopped by user request."
        exit 1
    fi
    echo ""
else
    echo "[Precheck] OK, selinux is enabled"
    echo ""
fi

echo "[Precheck] Precheck successful."
echo ""
echo ""

###############################################################################
# SECTION 2: USER INPUT
#
###############################################################################

echo "You must now specify a range of IP addresses that are free"
echo "for Eucalyptus to use.  These IP addresses should not be"
echo "taken up by any other machines, and should not be in any"
echo "DHCP address pools."
echo ""

until test -n "${efs_ip_range}" ; do
    echo "What's the CIDR for the available public IP range?"
    until valid_cidr "$efs_ip_cidr"; do
        readinput efs_ip_cidr
        valid_cidr "$efs_ip_cidr" || inputerror "Please provide a valid CIDR (/24 - /28):"
    done

    efs_ip_cidr_end=$(echo "$efs_ip_cidr" | cut -d '.' -f 4)
    efs_ip_cidr_q4="${efs_ip_cidr_end%%/*}"
    efs_ip_cidr_pre="${efs_ip_cidr_end##*/}"
    efs_ip_range_start="${efs_ip_cidr%%/*}"
    efs_ip_range_end="${efs_ip_cidr%%/*}"
    efs_ip_range_start="${efs_ip_range_start%%.${efs_ip_cidr_q4}}.$((efs_ip_cidr_q4+1))"
    efs_ip_range_end="${efs_ip_range_end%%.${efs_ip_cidr_q4}}.$((efs_ip_cidr_q4+(2 ** (32-efs_ip_cidr_pre))-2))"
    efs_ip_range="${efs_ip_range_start}-${efs_ip_range_end}"

    echo ""
    echo "OK, public IP address CIDR is good."
    echo ""
    echo "  Public cidr will be :  $efs_ip_cidr"
    echo "  Public range will be   $efs_ip_range"
    echo ""
done

###############################################################################
# SECTION 3: PREP Ansible Playbook Artifacts
#
###############################################################################

echo "[Ansible] Installing EPEL release package"
yum install -q -y epel-release 1>&4

echo "[Ansible] Installing Eucalyptus release package"
yum install -q -y "${eucalyptus_release}" 1>&4

echo "[Ansible] Installing Eucalyptus ansible package"
yum install -q -y "eucalyptus-ansible" 1>&4

# YUM repository is as per the installed eucalyptus release rpm
efs_yum_base_url=$(grep "baseurl" "/etc/yum.repos.d/eucalyptus.repo" | cut -d = -f 2)

echo "[Ansible] Generating ansible inventory"
cat > "${efs_inventory}" <<TEMPLATE
---
all:
  hosts:
    host1:
      ansible_connection: local
  vars:
    eucalyptus_yum_baseurl: "${efs_yum_base_url}"

    cloud_firewalld_cluster_cidr: "{{ ansible_default_ipv4.address }}/32"
    cloud_firewalld_configure: ${efs_firewalld_configure}

    cloud_system_dns_dnsdomain: "cloud-{{ ansible_default_ipv4.address|replace('.', '-') }}.euca.me"

    # If enabled deployment must be public
    eucaconsole_certbot_configure: ${efs_certbot_configure}

    vpcmido_public_ip_range: ${efs_ip_range}
    vpcmido_public_ip_cidr: ${efs_ip_cidr}

  children:
    cloud:
      hosts:
        host1:
    # Optional management console remove if not required
    console:
      hosts:
        host1:
TEMPLATE

if [ "${efs_inventory_only}" = "yes" ] ; then
  echo "Generated inventory:"
  echo ""
  echo "  ${efs_inventory}"
  echo ""
  echo "To install using playbook run:"
  echo ""
  echo "  ansible-playbook -i ${efs_inventory} /usr/share/eucalyptus-ansible/playbook_vpcmido.yml"
  echo ""
  exit 0
fi

###############################################################################
# SECTION 4: INSTALL EUCALYPTUS
#
###############################################################################

# Install Eucalyptus.
echo ""
echo ""
echo "[Installing Eucalyptus]"
echo ""
echo "If you want to watch the progress of this installation, you can check the"
echo "log file by running the following command in another terminal:"
echo ""
echo "  tail -f $LOGFILE"
echo ""
echo "Your cloud-in-a-box should be installed in 20-30 minutes. Go have a cup of tea!"
echo ""

# To make the spinner work, we need to launch in a subshell.  Since we
# can't get variables from the subshell scope, we'll write success or
# failure to a file, and then succeed or fail based on whether the file
# exists or not.

rm -f faststart-successful*.log

echo "[Yum Update] OK, running a full update of the OS. This could take a bit; please wait."
echo ""
echo "To see the update in progress, run the following command in another terminal:"
echo ""
echo "  tail -f $LOGFILE"
echo ""
echo "[Yum Update] Package update in progress..."
(yum -y update && echo "Phase 0 success" > faststart-successful-phase0.log) 1>&4 2>&4 &
tea $!

if [[ ! -f faststart-successful-phase0.log ]]; then
    echo "====="
    echo "[FATAL] Yum update failed!"
    echo ""
    echo "Failed to do a full update of the OS. See $LOGFILE for details. /var/log/yum.log"
    echo "may also have some details related to the same."
    exit 24
fi
echo "[Yum Update] Full update of the OS completed."

# Run ansible playbook
# On successful exit, write "success" to faststart-successful*.log.

(ansible-playbook --inventory "${efs_inventory}" \
  --skip-tags "${efs_skip_tags}" \
  /usr/share/eucalyptus-ansible/playbook_vpcmido.yml && \
  echo "Phase 1 success" > faststart-successful-phase1.log) 1>&4 2>&4 &

echo ""
echo "Phase 0 (OS) completed successfully...getting a 2nd cup of tea and moving on to phase 1 (Eucalyptus)."
tea $!

if [[ ! -f faststart-successful-phase1.log ]]; then
    echo "[FATAL] Eucalyptus installation failed"
    echo ""
    echo "Eucalyptus installation failed. Please consult $LOGFILE for details."
    echo ""
    echo "Please try to run the installation again. If your installation fails again,"
    echo "you can ask the Eucalyptus community for assistance:"
    echo ""
    echo "https://stackoverflow.com/questions/tagged/eucalyptus"
    echo ""
    echo "Or find us on IRC at irc.freenode.net, on the #eucalyptus channel."
    echo ""
    exit 99
  else
    echo "Phase 1 (Eucalyptus) completed successfully."
fi

###############################################################################
# SECTION 5: POST-INSTALL CONFIGURATION
#
# If we reach this section, install has been successful.
###############################################################################

echo ""
echo "[SUCCESS] Eucalyptus installation complete!"
total_time=$(timer "$t")
printf 'Time to install: %s\n' "$total_time"
echo ""
echo "[Config] To enable eucalyptus/admin web console access run:"
echo ""
echo "  euare-useraddloginprofile --as-account eucalyptus -u admin -p PASSWORD"
echo ""
echo "[Config] To generate/import an SSH keypair run:"
echo ""
echo "  [ -f ~/.ssh/id_rsa ] || ssh-keygen -N '' -f ~/.ssh/id_rsa"
echo "  euca-import-keypair -f ~/.ssh/id_rsa.pub KEYNAME"
echo ""
echo "[Config] To enable instance SSH access in the default security group run:"
echo ""
echo "  euca-authorize -P tcp -p 22 default"
echo ""
echo "[Config] To add machine images (ami/emi) to your cloud run:"
echo ""
echo "  eucalyptus-images"
echo ""
echo "Thanks for installing Eucalyptus!"

exit 0

} # end function faststart

faststart_init "$@"
exec 3>&1
exec 4>"${LOGFILE}"
if [ $batch_mode -eq 1 ] ; then
  faststart <&0- 2>&1 | tee /dev/fd/4  # no stdin
else
  faststart | tee /dev/fd/4
fi

