/**
 * hugo build の出力HTML（public/en と public/ja）をページ単位でペアリングし、
 * 本文コンテナ（article#content）のDOM構造骨格を比較する。
 *
 * Markdownレベルのパリティ検証（check-structure-parity.sh）では捉えられない
 * 「レンダリング結果としての構造差分」を検出する最終検証（E2E相当）。
 * テキストノードと言語依存の属性（見出しid等）は比較しない。
 *
 * 比較する不変量:
 *   - 見出し（h1-h6）のレベル順列
 *   - コードブロック（pre code）の数と正規化テキストのハッシュ（コードは翻訳されない）
 *   - 画像の数と src ファイル名の順列
 *   - 外部リンク（http/https）のURL集合
 *   - 内部リンクの本数
 *   - 構造コンテナ（.tabs / .callout / table / details）の種類と順列
 *
 * 使い方: npx tsx compare-rendered-structure.ts <site_root> [--report <json_path>]
 *   <site_root> は en/ と ja/ を含むhugo出力ディレクトリ
 *
 * 出力: 不一致を "RENDER <path>: <詳細>" 、en対応ページのないja側ページを
 *       "RENDER-ORPHAN <path>: ..." としてstdoutへ1行ずつ出力
 * 終了コード: 0 = 不一致なし、1 = 不一致あり、2 = 引数・入出力エラー
 */
import * as fs from "node:fs";
import * as path from "node:path";
import * as crypto from "node:crypto";
import * as cheerio from "cheerio";

interface PageSkeleton {
  headings: string[];
  codeBlocks: string[];
  images: string[];
  externalLinks: string[];
  internalLinkCount: number;
  containers: string[];
}

interface PageIssue {
  page: string;
  labels: string[];
}

function listIndexHtml(root: string): string[] {
  const results: string[] = [];
  const walk = (dir: string) => {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name === "index.html") results.push(full);
    }
  };
  walk(root);
  return results.sort();
}

function shortHash(text: string): string {
  return crypto.createHash("sha1").update(text).digest("hex").slice(0, 8);
}

/** ページを読み、リダイレクト（alias）ページなら null を返す */
function extractSkeleton(filePath: string): PageSkeleton | "redirect" | "no-content" {
  const html = fs.readFileSync(filePath, "utf8");
  const $ = cheerio.load(html);

  if ($('meta[http-equiv="refresh"]').length > 0 && $("article#content").length === 0) {
    return "redirect";
  }
  const article = $("article#content");
  if (article.length === 0) {
    return "no-content";
  }

  // パンくず・ページャー・TOC等のナビゲーションは、ja側の未翻訳ページの有無で
  // リンク数が正当に変わるため比較対象から除外する（本文構造のみを比較する）
  article.find("nav, aside").remove();

  const headings: string[] = [];
  article.find("h1, h2, h3, h4, h5, h6").each((_, el) => {
    headings.push((el as any).tagName ?? (el as any).name);
  });

  const codeBlocks: string[] = [];
  article.find("pre code").each((_, el) => {
    const normalized = $(el).text().replace(/\s+/g, " ").trim();
    codeBlocks.push(shortHash(normalized));
  });

  const images: string[] = [];
  article.find("img").each((_, el) => {
    const src = $(el).attr("src") ?? "";
    images.push(path.basename(src.split(/[?#]/)[0]));
  });

  const externalLinks = new Set<string>();
  let internalLinkCount = 0;
  article.find("a[href]").each((_, el) => {
    const href = $(el).attr("href") ?? "";
    if (/^https?:\/\//.test(href)) externalLinks.add(href);
    else internalLinkCount += 1;
  });

  const containers: string[] = [];
  article.find(".tabs, .callout, table, details").each((_, el) => {
    const $el = $(el);
    if ($el.hasClass("tabs")) {
      containers.push(`tabs(${$el.find(".tabs__panel").length})`);
    } else if ($el.hasClass("callout")) {
      const modifier =
        ($el.attr("class") ?? "")
          .split(/\s+/)
          .find((c) => c.startsWith("callout--")) ?? "callout";
      containers.push(modifier);
    } else {
      containers.push((el as any).tagName ?? (el as any).name);
    }
  });

  return { headings, codeBlocks, images, externalLinks: [...externalLinks].sort(), internalLinkCount, containers };
}

function compareSeq(label: string, en: string[], ja: string[], labels: string[]) {
  if (en.length !== ja.length) {
    labels.push(`${label} count differs (en=${en.length} ja=${ja.length})`);
    return;
  }
  for (let i = 0; i < en.length; i++) {
    if (en[i] !== ja[i]) {
      labels.push(`${label} sequence differs at #${i + 1} (en=${en[i]} ja=${ja[i]})`);
      return;
    }
  }
}

function main(): number {
  const args = process.argv.slice(2);
  const reportIdx = args.indexOf("--report");
  let reportPath: string | undefined;
  if (reportIdx >= 0) {
    reportPath = args[reportIdx + 1];
    args.splice(reportIdx, 2);
  }
  const siteRoot = args[0];
  if (!siteRoot || !fs.existsSync(path.join(siteRoot, "en")) || !fs.existsSync(path.join(siteRoot, "ja"))) {
    console.error("Usage: compare-rendered-structure.ts <site_root with en/ and ja/> [--report out.json]");
    return 2;
  }

  const enRoot = path.join(siteRoot, "en");
  const jaRoot = path.join(siteRoot, "ja");

  const jaPages = listIndexHtml(jaRoot).map((p) => path.relative(jaRoot, p));
  const enPages = new Set(listIndexHtml(enRoot).map((p) => path.relative(enRoot, p)));

  const issues: PageIssue[] = [];
  const orphans: string[] = [];
  let compared = 0;
  let skippedRedirects = 0;

  for (const rel of jaPages) {
    const jaFile = path.join(jaRoot, rel);
    const jaSkel = extractSkeleton(jaFile);
    if (jaSkel === "redirect") {
      skippedRedirects += 1;
      continue;
    }

    if (!enPages.has(rel)) {
      orphans.push(rel);
      continue;
    }

    const enSkel = extractSkeleton(path.join(enRoot, rel));
    if (enSkel === "redirect") {
      skippedRedirects += 1;
      continue;
    }

    const labels: string[] = [];
    if (jaSkel === "no-content" || enSkel === "no-content") {
      if (jaSkel !== enSkel) {
        labels.push(`content container missing on one side (en=${typeof enSkel === "string" ? enSkel : "ok"} ja=${typeof jaSkel === "string" ? jaSkel : "ok"})`);
      }
      // 両側とも本文コンテナなし（特殊レイアウトページ）は比較対象外
    } else {
      compared += 1;
      compareSeq("heading", enSkel.headings, jaSkel.headings, labels);
      compareSeq("code block", enSkel.codeBlocks, jaSkel.codeBlocks, labels);
      compareSeq("image", enSkel.images, jaSkel.images, labels);
      compareSeq("container", enSkel.containers, jaSkel.containers, labels);
      if (enSkel.externalLinks.join("\n") !== jaSkel.externalLinks.join("\n")) {
        labels.push(`external link set differs (en=${enSkel.externalLinks.length} ja=${jaSkel.externalLinks.length})`);
      }
      if (enSkel.internalLinkCount !== jaSkel.internalLinkCount) {
        labels.push(`internal link count differs (en=${enSkel.internalLinkCount} ja=${jaSkel.internalLinkCount})`);
      }
    }

    if (labels.length > 0) issues.push({ page: rel, labels });
  }

  // en側にしかないページ数（未翻訳。警告ではなく情報として集計のみ）
  const jaSet = new Set(jaPages);
  const enOnlyCount = [...enPages].filter((p) => !jaSet.has(p)).length;

  for (const issue of issues) {
    for (const label of issue.labels) {
      console.log(`RENDER ${issue.page}: ${label}`);
    }
  }
  for (const orphan of orphans) {
    console.log(`RENDER-ORPHAN ${orphan}: Japanese page has no English counterpart`);
  }

  console.log(
    `Summary: compared=${compared} pages_with_issues=${issues.length} ja_orphan_pages=${orphans.length} en_only_pages=${enOnlyCount} skipped_redirects=${skippedRedirects}`,
  );

  if (reportPath) {
    fs.writeFileSync(
      reportPath,
      JSON.stringify({ compared, enOnlyCount, orphans, issues, skippedRedirects }, null, 2),
    );
  }

  return issues.length > 0 || orphans.length > 0 ? 1 : 0;
}

process.exit(main());
