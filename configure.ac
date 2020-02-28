m4_define([base_version], [5.0.100])
m4_define([git_revision],
          m4_esyscmd([git rev-parse HEAD | cut -c-7 | tr -d '\n']))
m4_define([git_commit_count],
          m4_esyscmd([git log --pretty=format: HEAD | wc -l | tr -d '\n']))
m4_define([date], m4_esyscmd([date +%Y%m%d | tr -d '\n']))
m4_define([fullversion], [base_version-git_commit_count-date[git]git_revision])

AC_INIT([eucalyptus-ansible], [fullversion])

PLAYBOOK_COMMIT=6dd0d9d64d6e0266b101f3d15a756c19ba3e79c8

AC_ARG_WITH(playbook-commit,
    [  --with-playbook-commit=<commit>       the ats-deploy commit],
    [PLAYBOOK_COMMIT="${withval}"])

AC_CONFIG_FILES([
    Makefile
])
AC_SUBST(PLAYBOOK_COMMIT)
AC_OUTPUT
