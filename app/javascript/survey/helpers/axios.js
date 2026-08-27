import axios from 'axios';
import { APP_BASE_URL } from 'widget/helpers/constants';

// Prefix API calls with the sub-path the app is deployed under (e.g. '/helpengine'), the
// same way the dashboard's ApiClient does. The survey endpoints are root-relative
// ('/public/api/v1/csat_survey/…'); without this they leave the app's nginx location
// and the rating never saves.
const basePath = window.chatwootConfig?.basePath || APP_BASE_URL;

export const API = axios.create({
  baseURL: basePath,
});
