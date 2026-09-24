/// App Store 3.1.1 / Google Play billing: paid tiers that unlock in-app features
/// can't be priced, requested or linked to an outside payment inside the app.
/// While this is false the app never shows plan prices or the "Go official"
/// request; admins still grant Official clubs and partner plans by hand after
/// the owner pays TT Spot directly. Flip only for builds that never go through
/// a store (or once in-app purchases exist).
const kShowPlanPricing = false;
