Name:           eucalyptus-ansible
Version:        5.0.101
Release:        0%{?build_id:.%build_id}%{?dist}
Summary:        Ansible playbooks for Eucalyptus

License:        GPLv2
URL:            https://github.com/corymbia/eucalyptus-ansible
Source0:        %{tarball_basedir}.tar.xz

BuildArch:      noarch

Requires:       ansible >= 2.4.2.0


%description
Ansible playbooks for installation and management of Eucalyptus cloud
deployments.


%prep
%setup -q -n %{tarball_basedir}


%install
mkdir -p $RPM_BUILD_ROOT/usr/share/%{name}
cp -rp * $RPM_BUILD_ROOT/usr/share/%{name}/


%files
/usr/share/%{name}


%changelog
* Thu Feb 20 2020 Steve Jones <steve.jones@appscale.com>
- Created

