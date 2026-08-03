import { createRouter, createWebHistory } from 'vue-router';

import routes from './routes';
import AnalyticsHelper from 'dashboard/helper/AnalyticsHelper';
import { basePath } from 'dashboard/helper/URLHelper';
import { validateRouteAccess } from '../helpers/RouteHelper';

export const router = createRouter({
  history: createWebHistory(basePath()),
  routes,
});

const sensitiveRouteNames = ['auth_password_edit'];

export const initalizeRouter = () => {
  router.beforeEach((to, _, next) => {
    if (!sensitiveRouteNames.includes(to.name)) {
      AnalyticsHelper.page(to.name || '', {
        path: to.path,
        name: to.name,
      });
    }

    return validateRouteAccess(to, next, window.chatwootConfig);
  });
};

export default router;
