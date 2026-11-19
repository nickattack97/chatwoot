#!/bin/bash
# Retired. This script copied a developer's working copy to the production server, built `cbz-helpengine:latest` there and
# restarted it: no version, no record of who deployed what, and migrations after the restart.
#
# Releases now go through the GitLab pipeline (.gitlab-ci.yml):
#   UAT          tag helpengine-vX.Y.Z-rc.N on a dev commit
#   production   tag helpengine-vX.Y.Z on a master commit
# See DEPLOYMENT.md → "Pipeline".
echo "deploy.sh is retired: release through the GitLab pipeline (DEPLOYMENT.md → Pipeline)." >&2
exit 1
