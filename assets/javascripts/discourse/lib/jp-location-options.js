const PREFECTURES = [
  "北海道",
  "青森県",
  "岩手県",
  "宮城県",
  "秋田県",
  "山形県",
  "福島県",
  "茨城県",
  "栃木県",
  "群馬県",
  "埼玉県",
  "千葉県",
  "東京都",
  "神奈川県",
  "新潟県",
  "富山県",
  "石川県",
  "福井県",
  "山梨県",
  "長野県",
  "岐阜県",
  "静岡県",
  "愛知県",
  "三重県",
  "滋賀県",
  "京都府",
  "大阪府",
  "兵庫県",
  "奈良県",
  "和歌山県",
  "鳥取県",
  "島根県",
  "岡山県",
  "広島県",
  "山口県",
  "徳島県",
  "香川県",
  "愛媛県",
  "高知県",
  "福岡県",
  "佐賀県",
  "長崎県",
  "熊本県",
  "大分県",
  "宮崎県",
  "鹿児島県",
  "沖縄県"
];

const CITY_BY_PREFECTURE = {
  "北海道": ["札幌市"],
  "青森県": ["青森市"],
  "岩手県": ["盛岡市"],
  "宮城県": ["仙台市"],
  "秋田県": ["秋田市"],
  "山形県": ["山形市"],
  "福島県": ["福島市"],
  "茨城県": ["水戸市"],
  "栃木県": ["宇都宮市"],
  "群馬県": ["前橋市"],
  "埼玉県": ["さいたま市", "川口市", "川越市", "所沢市", "越谷市"],
  "千葉県": ["千葉市", "船橋市", "市川市", "松戸市", "柏市"],
  "東京都": [
    "千代田区",
    "中央区",
    "港区",
    "新宿区",
    "文京区",
    "台東区",
    "墨田区",
    "江東区",
    "品川区",
    "目黒区",
    "大田区",
    "世田谷区",
    "渋谷区",
    "中野区",
    "杉並区",
    "豊島区",
    "北区",
    "荒川区",
    "板橋区",
    "練馬区",
    "足立区",
    "葛飾区",
    "江戸川区",
    "八王子市",
    "立川市",
    "武蔵野市",
    "三鷹市",
    "府中市",
    "町田市",
    "調布市"
  ],
  "神奈川県": ["横浜市", "川崎市", "相模原市", "藤沢市", "鎌倉市", "横須賀市"],
  "新潟県": ["新潟市"],
  "富山県": ["富山市"],
  "石川県": ["金沢市"],
  "福井県": ["福井市"],
  "山梨県": ["甲府市"],
  "長野県": ["長野市"],
  "岐阜県": ["岐阜市"],
  "静岡県": ["静岡市", "浜松市"],
  "愛知県": ["名古屋市"],
  "三重県": ["津市"],
  "滋賀県": ["大津市"],
  "京都府": ["京都市", "宇治市", "亀岡市"],
  "大阪府": ["大阪市", "堺市", "豊中市", "吹田市", "高槻市", "東大阪市"],
  "兵庫県": ["神戸市", "姫路市", "尼崎市", "西宮市", "明石市"],
  "奈良県": ["奈良市"],
  "和歌山県": ["和歌山市"],
  "鳥取県": ["鳥取市"],
  "島根県": ["松江市"],
  "岡山県": ["岡山市"],
  "広島県": ["広島市"],
  "山口県": ["山口市", "下関市"],
  "徳島県": ["徳島市"],
  "香川県": ["高松市"],
  "愛媛県": ["松山市"],
  "高知県": ["高知市"],
  "福岡県": ["福岡市", "北九州市", "久留米市", "春日市", "大野城市"],
  "佐賀県": ["佐賀市"],
  "長崎県": ["長崎市", "佐世保市"],
  "熊本県": ["熊本市"],
  "大分県": ["大分市"],
  "宮崎県": ["宮崎市"],
  "鹿児島県": ["鹿児島市"],
  "沖縄県": ["那覇市"]
};

const CHAR_FOLD = {
  冈: "岡",
  县: "県",
  縣: "県",
  东: "東",
  长: "長",
  岛: "島",
  广: "広",
  冲: "沖",
  贺: "賀",
  爱: "愛",
  叶: "葉",
  户: "戸",
  涩: "渋",
  澀: "渋"
};

function foldText(raw) {
  let out = String(raw || "").trim();
  for (const [from, to] of Object.entries(CHAR_FOLD)) {
    out = out.replaceAll(from, to);
  }
  return out;
}

function stripSuffix(raw) {
  return String(raw || "").replace(/[都道府県]/g, "");
}

function normalizeToken(raw) {
  return stripSuffix(foldText(raw));
}

function normalizeCityToken(raw) {
  return foldText(raw).replace(/[市区區町村郡]/g, "");
}

const PREFECTURE_CANONICAL = new Map();
for (const pref of PREFECTURES) {
  PREFECTURE_CANONICAL.set(normalizeToken(pref), pref);
}

export function resolvePrefectureName(raw) {
  const token = normalizeToken(raw);
  if (!token) return "";
  return PREFECTURE_CANONICAL.get(token) || "";
}

export function prefectureOptions() {
  return PREFECTURES.map((name) => ({ code: name, name }));
}

export function cityOptionsByPrefecture(prefecture, currentCity = "") {
  const canonical = resolvePrefectureName(prefecture) || prefecture;
  const base = (CITY_BY_PREFECTURE[canonical] || []).slice();
  const city = String(currentCity || "").trim();
  if (city && !base.includes(city)) {
    base.push(city);
  }
  return base.map((name) => ({ code: name, name }));
}

export function resolveCityName(prefecture, raw) {
  const city = String(raw || "").trim();
  if (!city) return "";

  const token = normalizeCityToken(city);
  const hasMunicipalitySuffix = /[市区區町村]\s*$/.test(city);
  if (!hasMunicipalitySuffix && token.length < 2) {
    return city;
  }

  const options = cityOptionsByPrefecture(prefecture).map((option) => option.name);
  return options.find((option) => normalizeCityToken(option) === token) || city;
}
