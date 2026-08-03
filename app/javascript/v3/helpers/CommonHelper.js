import { absoluteURL } from 'dashboard/helper/URLHelper';

// Full page navigation — bypasses vue-router, so root-relative in-app paths
// need the deployment base path applied explicitly.
export const replaceRouteWithReload = url => {
  window.location = absoluteURL(url);
};

export const userInitial = name => {
  const parts = name.split(/[ -]/).filter(Boolean);
  let initials = parts.map(part => part[0].toUpperCase()).join('');
  return initials.slice(0, 2);
};
