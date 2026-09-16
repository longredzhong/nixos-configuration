/*
 * Minimal Markdown renderer for the built-in documentation reader.
 *
 * The portal serves the repository's own `docs/*.md` files verbatim, so the
 * reader only needs the subset those documents actually use: ATX headings,
 * fenced code, tables, ordered/unordered lists, blockquotes, horizontal rules,
 * and inline code/bold/italic/links.
 *
 * All text is HTML-escaped before any markup is emitted, and link targets are
 * restricted to safe schemes.
 */
(function () {
  "use strict";

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function inline(text, codes) {
    var out = escapeHtml(text);

    out = out.replace(/`([^`]+)`/g, function (_match, code) {
      codes.push(code);
      return "\u0000" + (codes.length - 1) + "\u0000";
    });

    out = out.replace(/\[([^\]]+)\]\(([^)\s]+)\)/g, function (_match, label, href) {
      var safe = /^(https?:|mailto:|#|\/)/i.test(href) ? href : "#";
      return (
        '<a href="' +
        safe +
        '" target="_blank" rel="noreferrer noopener">' +
        label +
        "</a>"
      );
    });

    out = out.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    out = out.replace(/(^|[^*])\*([^*]+)\*/g, "$1<em>$2</em>");

    return out.replace(/\u0000(\d+)\u0000/g, function (_match, index) {
      return "<code>" + codes[Number(index)] + "</code>";
    });
  }

  function splitRow(line) {
    return line
      .trim()
      .replace(/^\|/, "")
      .replace(/\|$/, "")
      .split("|")
      .map(function (cell) {
        return cell.trim();
      });
  }

  function renderTable(lines, index) {
    var header = splitRow(lines[index]);
    var align = splitRow(lines[index + 1]).map(function (cell) {
      if (/^:-+:$/.test(cell)) return "center";
      if (/^-+:$/.test(cell)) return "right";
      return "left";
    });
    var body = [];
    var cursor = index + 2;
    while (cursor < lines.length && /\|/.test(lines[cursor]) && lines[cursor].trim()) {
      body.push(splitRow(lines[cursor]));
      cursor += 1;
    }

    var codes = [];
    var html = ['<div class="md-table-wrap"><table><thead><tr>'];
    header.forEach(function (cell, cellIndex) {
      html.push(
        '<th style="text-align:' +
          (align[cellIndex] || "left") +
          '">' +
          inline(cell, codes) +
          "</th>"
      );
    });
    html.push("</tr></thead><tbody>");
    body.forEach(function (row) {
      html.push("<tr>");
      header.forEach(function (_cell, cellIndex) {
        html.push("<td>" + inline(row[cellIndex] || "", codes) + "</td>");
      });
      html.push("</tr>");
    });
    html.push("</tbody></table></div>");
    return { html: html.join(""), next: cursor };
  }

  function render(source) {
    var lines = String(source || "").replace(/\r\n?/g, "\n").split("\n");
    var html = [];
    var codes = [];
    var index = 0;

    function flushParagraph(buffer) {
      if (!buffer.length) return;
      html.push("<p>" + inline(buffer.join(" "), codes) + "</p>");
      buffer.length = 0;
    }

    var paragraph = [];

    while (index < lines.length) {
      var line = lines[index];

      // Fenced code block
      var fence = line.match(/^\s*```(.*)$/);
      if (fence) {
        flushParagraph(paragraph);
        var language = fence[1].trim();
        var codeLines = [];
        index += 1;
        while (index < lines.length && !/^\s*```\s*$/.test(lines[index])) {
          codeLines.push(lines[index]);
          index += 1;
        }
        index += 1;
        html.push(
          '<pre class="md-code"' +
            (language ? ' data-language="' + escapeHtml(language) + '"' : "") +
            "><code>" +
            escapeHtml(codeLines.join("\n")) +
            "</code></pre>"
        );
        continue;
      }

      // Table
      if (
        /\|/.test(line) &&
        index + 1 < lines.length &&
        /^\s*\|?[\s:|-]+\|[\s:|-]*$/.test(lines[index + 1])
      ) {
        flushParagraph(paragraph);
        var table = renderTable(lines, index);
        html.push(table.html);
        index = table.next;
        continue;
      }

      var heading = line.match(/^(#{1,6})\s+(.*)$/);
      if (heading) {
        flushParagraph(paragraph);
        var level = heading[1].length;
        html.push(
          "<h" + level + ">" + inline(heading[2], codes) + "</h" + level + ">"
        );
        index += 1;
        continue;
      }

      if (/^\s*(-{3,}|\*{3,})\s*$/.test(line)) {
        flushParagraph(paragraph);
        html.push("<hr>");
        index += 1;
        continue;
      }

      if (/^\s*>\s?/.test(line)) {
        flushParagraph(paragraph);
        var quote = [];
        while (index < lines.length && /^\s*>\s?/.test(lines[index])) {
          quote.push(lines[index].replace(/^\s*>\s?/, ""));
          index += 1;
        }
        html.push("<blockquote>" + inline(quote.join(" "), codes) + "</blockquote>");
        continue;
      }

      var bullet = line.match(/^\s*[-*+]\s+(.*)$/);
      var ordered = line.match(/^\s*\d+[.)]\s+(.*)$/);
      if (bullet || ordered) {
        flushParagraph(paragraph);
        var tag = bullet ? "ul" : "ol";
        var items = [];
        while (index < lines.length) {
          var nextBullet = lines[index].match(/^\s*[-*+]\s+(.*)$/);
          var nextOrdered = lines[index].match(/^\s*\d+[.)]\s+(.*)$/);
          if (tag === "ul" && nextBullet) items.push(nextBullet[1]);
          else if (tag === "ol" && nextOrdered) items.push(nextOrdered[1]);
          else break;
          index += 1;
        }
        html.push(
          "<" +
            tag +
            ">" +
            items
              .map(function (item) {
                return "<li>" + inline(item, codes) + "</li>";
              })
              .join("") +
            "</" +
            tag +
            ">"
        );
        continue;
      }

      if (!line.trim()) {
        flushParagraph(paragraph);
        index += 1;
        continue;
      }

      paragraph.push(line.trim());
      index += 1;
    }

    flushParagraph(paragraph);
    return html.join("\n");
  }

  window.renderMarkdown = render;
  window.escapeHtml = escapeHtml;
})();
