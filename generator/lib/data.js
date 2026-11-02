'use strict';
// Deterministic synthetic data for Laheey Wholesale Ops.
// Every value is invented. Emails use example.com and phones use the 555-01xx fictional range.

// ---------- seeded random numbers (mulberry32) ----------
function rng(seed) {
  let a = seed >>> 0;
  const next = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  return {
    next,
    int: (lo, hi) => lo + Math.floor(next() * (hi - lo + 1)),
    pick: (arr) => arr[Math.floor(next() * arr.length)],
    chance: (p) => next() < p,
    weighted: (pairs) => {          // [[value, weight], ...]
      const total = pairs.reduce((s, p) => s + p[1], 0);
      let r = next() * total;
      for (const [v, w] of pairs) { if ((r -= w) < 0) return v; }
      return pairs[pairs.length - 1][0];
    },
  };
}

// Pick an index from a cumulative-weight array with binary search (O(log n))
function pickCumulative(cum, r) {
  const target = r * cum[cum.length - 1];
  let lo = 0, hi = cum.length - 1;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (cum[mid] < target) lo = mid + 1; else hi = mid;
  }
  return lo;
}

// ---------- dates (UTC day numbers, so no time-zone drift) ----------
const DAY = 86400000;
const toDay = (iso) => Math.floor(Date.parse(iso + 'T00:00:00Z') / DAY);
const fromDay = (d) => new Date(d * DAY).toISOString().slice(0, 10);

// Orders peak in Nov-Dec (holiday gifting, office parties) and dip in summer
const MONTH_WEIGHT = [0.85, 0.8, 0.9, 0.95, 1.0, 0.85, 0.8, 0.82, 0.95, 1.05, 1.3, 1.45];

// ---------- vocabularies ----------
const PLACES = ['Blue Door', 'Rosewood', 'Capitol', 'Anacostia', 'Harbor', 'Union', 'Brightside', 'Laurel', 'Columbia',
  'Rock Creek', 'Potomac', 'Fairmont', 'Hilltop', 'Northside', 'Cedar', 'Ivy', 'Old Town', 'Riverside', 'Benning', 'Shaw',
  'Takoma', 'Silver Spring', 'Eastern Market', 'Mount Vernon', 'Logan', 'Dupont', 'Fells Point', 'Hampden', 'Clarendon',
  'Ballston', 'Bethesda', 'Wheaton', 'Greenbelt', 'Annapolis', 'Frederick', 'Sunrise', 'Juniper', 'Magnolia', 'Copper',
  'Liberty', 'Summit', 'Meridian', 'Lantern', 'Sparrow', 'Oak & Ember', 'Red Line', 'Waterfront', 'Mosaic', 'Highland', 'Abol'];

const SEGMENTS = {
  Cafe:       { w: 34, suffix: ['Cafe', 'Coffee Bar', 'Espresso', 'Coffee House', 'Roastery Cafe'] },
  Grocery:    { w: 18, suffix: ['Market', 'Grocers', 'Co-op', 'Fresh Market', 'Pantry'] },
  Office:     { w: 20, suffix: ['Partners', 'Labs', 'Group', 'Associates', 'Studios'] },
  Restaurant: { w: 16, suffix: ['Kitchen', 'Bistro', 'Eatery', 'Diner', 'Table'] },
  Hotel:      { w: 7,  suffix: ['Hotel', 'Inn', 'Suites', 'Lodge'] },
  University: { w: 5,  suffix: ['University Dining', 'College Cafe', 'Campus Market'] },
};

const CITIES = [
  ['Washington', 'DC', 14], ['Silver Spring', 'MD', 4], ['Bethesda', 'MD', 3], ['Laurel', 'MD', 3], ['Columbia', 'MD', 3],
  ['Baltimore', 'MD', 7], ['Annapolis', 'MD', 2], ['Rockville', 'MD', 3], ['Frederick', 'MD', 2], ['Arlington', 'VA', 5],
  ['Alexandria', 'VA', 4], ['Fairfax', 'VA', 3], ['Reston', 'VA', 2], ['Richmond', 'VA', 3], ['Philadelphia', 'PA', 4],
  ['New York', 'NY', 6], ['Brooklyn', 'NY', 3], ['Boston', 'MA', 3], ['Atlanta', 'GA', 3], ['Chicago', 'IL', 3],
  ['Minneapolis', 'MN', 2], ['Seattle', 'WA', 2], ['Denver', 'CO', 2], ['Austin', 'TX', 2], ['Houston', 'TX', 2],
  ['Columbus', 'OH', 2], ['Raleigh', 'NC', 2], ['Charlotte', 'NC', 2], ['Los Angeles', 'CA', 3], ['Oakland', 'CA', 2],
];

const FIRST = ['Abebe', 'Selam', 'Hana', 'Dawit', 'Meron', 'Yonas', 'Tigist', 'Samuel', 'Liya', 'Bethlehem', 'Maria', 'James',
  'Aisha', 'Carlos', 'Mei', 'David', 'Fatima', 'Kwame', 'Sofia', 'Daniel', 'Grace', 'Omar', 'Priya', 'Luis', 'Emma',
  'Noah', 'Olivia', 'Ethan', 'Zara', 'Mateo', 'Chloe', 'Isaac', 'Nadia', 'Kenji', 'Amara', 'Lucas', 'Rahel', 'Tomas',
  'Ruth', 'Elias', 'Imani', 'Jordan', 'Ana', 'Victor', 'Leah', 'Hassan', 'Camila', 'Andre', 'Naomi', 'Kebede'];
const LAST = ['Tesfaye', 'Bekele', 'Haile', 'Girma', 'Alemu', 'Mekonnen', 'Johnson', 'Williams', 'Garcia', 'Martinez', 'Kim',
  'Nguyen', 'Patel', 'Okafor', 'Mensah', 'Smith', 'Brown', 'Davis', 'Lopez', 'Wilson', 'Anderson', 'Thomas', 'Moore',
  'Jackson', 'Lee', 'Harris', 'Clark', 'Lewis', 'Robinson', 'Walker', 'Young', 'Allen', 'Wright', 'Scott', 'Hill',
  'Green', 'Adams', 'Baker', 'Gonzalez', 'Rivera', 'Campbell', 'Mitchell', 'Carter', 'Roberts', 'Assefa', 'Wolde', 'Desta',
  'Yilma', 'Abate', 'Kassa'];

const CONTACT_TITLES = [['Owner', 3], ['Purchasing Manager', 3], ['Accounts Payable', 2], ['Head Barista', 2], ['Operations Manager', 2], ['Chef', 1]];
const REPS = ['Selam Haile', 'Marcus Reed', 'Ana Lopez', 'Dawit Bekele', 'Priya Shah', 'Jordan Ellis', 'Meron Tesfaye', 'Chris Park'];

const ORIGINS = [
  ['Ethiopia Yirgacheffe', 1.25], ['Ethiopia Sidamo', 1.15], ['Ethiopia Guji', 1.2], ['Ethiopia Harrar', 1.2], ['Ethiopia Limu', 1.1],
  ['Kenya AA', 1.3], ['Rwanda Huye', 1.15], ['Burundi Kayanza', 1.1], ['Tanzania Peaberry', 1.1], ['Uganda Bugisu', 1.0],
  ['Colombia Huila', 1.05], ['Colombia Narino', 1.1], ['Guatemala Antigua', 1.1], ['Costa Rica Tarrazu', 1.15], ['Honduras Marcala', 1.0],
  ['Peru Cajamarca', 1.0], ['Brazil Cerrado', 0.9], ['Brazil Mogiana', 0.9], ['Mexico Chiapas', 0.95], ['Nicaragua Jinotega', 0.95],
  ['Sumatra Mandheling', 1.05], ['Papua New Guinea', 1.05], ['House Espresso Blend', 0.95], ['Morning Blend', 0.85], ['Swiss Water Decaf', 1.05],
];
const ROASTS = ['Light', 'Medium', 'Medium-Dark', 'Dark'];
const SIZES = [['12 oz', 14.5], ['2 lb', 34], ['5 lb', 78], ['Case 6x12 oz', 81]];

const CASE_REASONS = [['Late delivery', 22], ['Damaged bag', 9], ['Wrong grind', 10], ['Billing question', 18],
  ['Subscription change', 15], ['Equipment issue', 7], ['Product feedback', 12], ['Missing item', 7]];

const pad = (n, w) => String(n).padStart(w, '0');

module.exports = {
  rng, pickCumulative, toDay, fromDay, MONTH_WEIGHT, PLACES, SEGMENTS, CITIES, FIRST, LAST,
  CONTACT_TITLES, REPS, ORIGINS, ROASTS, SIZES, CASE_REASONS, pad,
};
