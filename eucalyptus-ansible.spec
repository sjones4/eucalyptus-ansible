Name:           eucalyptus-ansible
Version:        6.0.100
Release:        0%{?build_id:.%build_id}%{?dist}
Summary:        Ansible playbooks for Eucalyptus

License:        GPLv2
URL:            https://github.com/corymbia/eucalyptus-ansible
Source0:        %{tarball_basedir}.tar.xz

BuildArch:      noarch

Requires:       ansible >= 2.9


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
* Mon Mar 29 2021 Steve Jones <steve.jones@appscale.com> - 6.0.100
- Version bump (6.0.100)

* Thu Feb 20 2020 Steve Jones <steve.jones@appscale.com>
- Created

