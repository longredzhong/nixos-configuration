/*
 * Home Lab Portal frontend.
 *
 * No build step and no third-party runtime: the module serves these files
 * directly. Inventory metadata comes from /api/inventory, live state from
 * /api/status, and documentation from /api/docs.
 */
(function () {
  "use strict";

  var escapeHtml = window.escapeHtml;

  var STATE_LABELS = {
    up: "正常",
    degraded: "部分可用",
    down: "不可用",
    unknown: "未知",
  };

  var DEPLOYMENT_ROWS = [
    [
      "读取实时状态",
      "可以。后端与服务同机，直接读 systemd 单元、健康探针和本机 /proc。",
      "不能。Pages 是静态与边缘托管，无法访问 100.64.0.0/10 的 tailnet 地址。",
    ],
    [
      "访问边界",
      "由 tailnet ACL 和设备审批决定。服务只绑定 tailnet 地址，没有公网入口。",
      "默认公网可达，需要额外自建身份层才能限制访问。",
    ],
    [
      "所需组件",
      "一个 Home Manager 模块，与 deepseek-harness、openobserve 的部署模式一致。",
      "静态前端之外还需要 Worker 加 Tunnel 回源才能拿到状态数据。",
    ],
    [
      "跨机器状态",
      "与本机服务同网段，可直接查询 OpenObserve 的机群指标。",
      "要先穿过 Tunnel 才能到达观测后端，链路更长。",
    ],
    [
      "凭据处理",
      "复用 agenix 与本机运行时文件，凭据不离开家庭实验室主机。",
      "状态回源凭据要放到 Cloudflare 侧，扩大了信任范围。",
    ],
    [
      "离线可用性",
      "tailnet 内可用，不依赖公网与第三方可用性。",
      "依赖 Cloudflare 边缘网络与公网连通性。",
    ],
    [
      "变更与审计",
      "随仓库模块走 just apply / hm-switch，和其余服务同一条审计链路。",
      "独立于 Nix 仓库，需要额外的 CI 或手动 deploy 流程。",
    ],
    [
      "结论",
      "状态门户与内部引导页的主方案。",
      "只适合纯静态的对外引导页；不要用它承载需要 tailnet 的实时状态。",
    ],
  ];

  var state = {
    inventory: null,
    status: null,
    docs: [],
    activeCategory: "all",
    timer: null,
    failures: 0,
  };

  // ---------------------------------------------------------------- helpers

  function $(id) {
    return document.getElementById(id);
  }

  function fmtBytes(value) {
    if (value === null || value === undefined || isNaN(value)) return "—";
    var units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
    var size = Number(value);
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit += 1;
    }
    var digits = size >= 100 || unit === 0 ? 0 : 1;
    return size.toFixed(digits) + " " + units[unit];
  }

  function fmtDuration(seconds) {
    if (seconds === null || seconds === undefined || isNaN(seconds)) return "—";
    var total = Math.floor(seconds);
    var days = Math.floor(total / 86400);
    var hours = Math.floor((total % 86400) / 3600);
    var minutes = Math.floor((total % 3600) / 60);
    if (days > 0) return days + " 天 " + hours + " 小时";
    if (hours > 0) return hours + " 小时 " + minutes + " 分";
    return minutes + " 分 " + (total % 60) + " 秒";
  }

  function fmtAge(seconds) {
    if (seconds === null || seconds === undefined) return "未知";
    if (seconds < 90) return seconds + " 秒前";
    if (seconds < 5400) return Math.round(seconds / 60) + " 分钟前";
    return Math.round(seconds / 3600) + " 小时前";
  }

  function pill(stateName) {
    var label = STATE_LABELS[stateName] || stateName;
    return (
      '<span class="pill pill-' +
      escapeHtml(stateName) +
      '">' +
      escapeHtml(label) +
      "</span>"
    );
  }

  function meter(percent, stateName) {
    var value = Math.max(0, Math.min(100, Number(percent) || 0));
    return (
      '<div class="meter" role="img" aria-label="' +
      value +
      '%"><span class="meter-fill meter-' +
      escapeHtml(stateName || "up") +
      '" style="width:' +
      value +
      '%"></span></div>'
    );
  }

  function link(label, href, options) {
    var opts = options || {};
    var cls = opts.quiet ? "entry entry-quiet" : "entry";
    var badge = opts.badge
      ? ' <span class="badge">' + escapeHtml(opts.badge) + "</span>"
      : "";
    if (!href) {
      return (
        '<span class="' + cls + ' entry-text">' + escapeHtml(label) + badge + "</span>"
      );
    }
    var external = /^https?:/i.test(href);
    return (
      '<a class="' +
      cls +
      '" href="' +
      escapeHtml(href) +
      '"' +
      (external ? ' target="_blank" rel="noreferrer noopener"' : "") +
      ">" +
      escapeHtml(label) +
      badge +
      "</a>"
    );
  }

  function tailnetSuffix() {
    var tailnet = state.status && state.status.tailnet;
    return (tailnet && tailnet.tailnet_suffix) || "";
  }

  function tailscaleLinks(service) {
    var config = service.tailscale;
    if (!config) return [];
    var suffix = tailnetSuffix();
    if (!suffix) return [];
    var primary = config.primaryPort || (config.ports && config.ports[0]) || 443;
    var links = [
      link(
        "https://" + config.service + "." + suffix,
        "https://" + config.service + "." + suffix + "/"
      ),
    ];
    (config.ports || []).forEach(function (port) {
      if (port === primary) return;
      links.push(
        link(
          config.service + "." + suffix + ":" + port + "（协议端点）",
          null,
          { quiet: true }
        )
      );
    });
    return links;
  }

  function directLinks(service) {
    return (service.direct || []).map(function (entry) {
      var port = entry.port ? ":" + entry.port : "";
      var address = entry.scheme + "://" + entry.host + port;
      var browserSafe = entry.kind !== "api" && entry.kind !== "proxy";
      return link(entry.label + " · " + address, browserSafe ? address : null, {
        quiet: !browserSafe,
      });
    });
  }

  function publicLinks(service) {
    return (service.publicHosts || []).map(function (entry) {
      return link("https://" + entry.hostname, "https://" + entry.hostname + "/", {
        badge: "公网",
      });
    });
  }

  function docButton(service) {
    var doc = service.docs;
    if (!doc || !/\.md$/.test(doc)) return "";
    return (
      '<button type="button" class="button button-quiet" data-doc="' +
      escapeHtml(doc) +
      '">' +
      escapeHtml(doc) +
      "</button>"
    );
  }

  // ------------------------------------------------------------- rendering

  function renderOverview() {
    var host = state.status.host;
    var counts = state.status.counts;
    var tailnet = state.status.tailnet;
    var cards = [];

    cards.push(
      card(
        "运行时长",
        fmtDuration(host.uptime_seconds),
        host.hostname + " · " + (host.kernel || "内核未知")
      )
    );

    cards.push(
      card(
        "系统负载",
        host.load1 === null || host.load1 === undefined
          ? "—"
          : host.load1.toFixed(2),
        (host.cpu_count || "?") +
          " 核 · 负载占比 " +
          (host.load_percent === null || host.load_percent === undefined
            ? "—"
            : host.load_percent + "%"),
        host.load1 !== null ? meter(host.load_percent || 0, loadTone(host.load_percent)) : ""
      )
    );

    if (host.memory) {
      cards.push(
        card(
          "内存",
          fmtBytes(host.memory.used_bytes),
          "共 " +
            fmtBytes(host.memory.total_bytes) +
            " · 可用 " +
            fmtBytes(host.memory.available_bytes),
          meter(host.memory.used_percent, toneFor(host.memory.used_percent))
        )
      );
    }

    cards.push(
      card(
        "服务",
        counts.up + " / " + state.status.services.length + " 正常",
        [
          counts.degraded ? counts.degraded + " 部分可用" : null,
          counts.down ? counts.down + " 不可用" : null,
          counts.unknown ? counts.unknown + " 未知" : null,
        ]
          .filter(Boolean)
          .join(" · ") || "全部探针通过",
        meter(
          (counts.up / Math.max(state.status.services.length, 1)) * 100,
          counts.down ? "down" : counts.degraded ? "degraded" : "up"
        )
      )
    );

    cards.push(
      card(
        "Tailnet",
        tailnet.online ? "已连接" : "未连接",
        tailnet.tailnet_ip +
          " · " +
          tailnet.peers_online +
          "/" +
          tailnet.peer_count +
          " 台在线",
        "",
        tailnet.online ? "up" : "down"
      )
    );

    (host.disks || []).forEach(function (disk) {
      cards.push(
        card(
          disk.label || disk.path,
          disk.used_percent + "%",
          "已用 " +
            fmtBytes(disk.used_bytes) +
            " · 可用 " +
            fmtBytes(disk.free_bytes),
          meter(disk.used_percent, toneFor(disk.used_percent))
        )
      );
    });

    $("overview-cards").innerHTML = cards.join("");

    var localHost = (state.inventory.hosts || [])[0] || {};
    var details = [];
    (localHost.notes || []).forEach(function (note) {
      details.push('<li class="note">' + escapeHtml(note) + "</li>");
    });
    details.push(
      '<li class="note">主机名 <code>' +
        escapeHtml(host.hostname) +
        "</code> · CPU " +
        escapeHtml(String(host.cpu_count)) +
        " 核 · 进程 " +
        escapeHtml(
          String(host.processes_running || "?") + "/" + String(host.processes_total || "?")
        ) +
        "</li>"
    );
    details.push(
      '<li class="note">本次采集耗时 ' +
        escapeHtml(String(state.status.duration_ms)) +
        " ms · 结果缓存 " +
        escapeHtml(process_cache_hint()) +
        "</li>"
    );
    $("overview-detail").innerHTML = details.join("");
    $("overview-note").textContent =
      (localHost.role || "") + (localHost.target ? " · " + localHost.target : "");
  }

  function process_cache_hint() {
    var seconds = (state.inventory.site || {}).refreshSeconds || 15;
    return seconds + " 秒内复用";
  }

  function toneFor(percent) {
    if (percent >= 90) return "down";
    if (percent >= 75) return "degraded";
    return "up";
  }

  function loadTone(percent) {
    if (percent === null || percent === undefined) return "up";
    if (percent >= 100) return "down";
    if (percent >= 70) return "degraded";
    return "up";
  }

  function card(title, value, subtitle, meterHtml, tone) {
    return [
      '<article class="card' + (tone ? " card-" + tone : "") + '">',
      '<h3 class="card-title">' + escapeHtml(title) + "</h3>",
      '<p class="card-value">' + escapeHtml(String(value)) + "</p>",
      subtitle ? '<p class="card-sub muted">' + escapeHtml(subtitle) + "</p>" : "",
      meterHtml || "",
      "</article>",
    ].join("");
  }

  function renderGuide() {
    var guide = state.inventory.guide || {};
    $("guide-summary").textContent = guide.summary || "";
    $("guide-steps").innerHTML = (guide.steps || [])
      .map(function (step, index) {
        return [
          '<li class="step">',
          '<span class="step-index" aria-hidden="true">' + (index + 1) + "</span>",
          '<div class="step-body"><h3>' + escapeHtml(step.title) + "</h3>",
          "<p>" + escapeHtml(step.body) + "</p></div>",
          "</li>",
        ].join("");
      })
      .join("");
  }

  function renderFilters() {
    var categories = state.inventory.categories || [];
    var items = [{ id: "all", name: "全部" }].concat(categories);
    $("service-filters").innerHTML = items
      .map(function (category) {
        var active = state.activeCategory === category.id;
        return (
          '<button type="button" class="chip' +
          (active ? " chip-active" : "") +
          '" data-category="' +
          escapeHtml(category.id) +
          '" aria-pressed="' +
          active +
          '">' +
          escapeHtml(category.name) +
          "</button>"
        );
      })
      .join("");
  }

  function renderServices() {
    var statusById = {};
    (state.status.services || []).forEach(function (entry) {
      statusById[entry.id] = entry;
    });

    var categories = state.inventory.categories || [];
    var byCategory = {};
    (state.inventory.services || []).forEach(function (service) {
      var key = service.category || "other";
      (byCategory[key] = byCategory[key] || []).push(service);
    });

    var html = [];
    categories.forEach(function (category) {
      var services = byCategory[category.id] || [];
      if (!services.length) return;
      if (state.activeCategory !== "all" && state.activeCategory !== category.id) return;

      var counts = { up: 0, degraded: 0, down: 0, unknown: 0 };
      services.forEach(function (service) {
        var value = (statusById[service.id] || {}).state || "unknown";
        counts[value] = (counts[value] || 0) + 1;
      });

      html.push('<div class="category">');
      html.push(
        '<div class="category-head"><h3>' +
          escapeHtml(category.name) +
          '</h3><p class="muted">' +
          escapeHtml(category.summary || "") +
          '</p><p class="category-count muted">' +
          escapeHtml(
            services.length +
              " 项 · 正常 " +
              counts.up +
              (counts.degraded ? " · 部分可用 " + counts.degraded : "") +
              (counts.down ? " · 不可用 " + counts.down : "") +
              (counts.unknown ? " · 未知 " + counts.unknown : "")
          ) +
          "</p></div>"
      );
      html.push(
        '<div class="service-grid">' +
          services.map(function (service) {
            return serviceCard(service, statusById[service.id] || {});
          }).join("") +
          "</div>"
      );
      html.push("</div>");
    });

    $("services-list").innerHTML = html.join("") || '<p class="muted">没有匹配的服务。</p>';
  }

  function serviceCard(service, live) {
    var rows = [];

    var unitRows = (live.units || []).map(function (unit) {
      return (
        '<li class="meta-row"><span class="meta-key">单元</span><span class="meta-value">' +
        '<code>' +
        escapeHtml(unit.unit) +
        "</code> " +
        pill(unit.active ? "up" : unit.known ? "down" : "unknown") +
        ' <span class="muted">' +
        escapeHtml(unit.state || "") +
        (unit.since ? " · 自 " + escapeHtml(unit.since) : "") +
        (unit.memory_bytes ? " · 内存 " + fmtBytes(unit.memory_bytes) : "") +
        (unit.restarts ? " · 重启 " + unit.restarts + " 次" : "") +
        "</span></span></li>"
      );
    });

    var extraRows = (live.extra_units || []).map(function (unit) {
      return (
        '<li class="meta-row"><span class="meta-key">定时器</span><span class="meta-value">' +
        '<code>' +
        escapeHtml(unit.unit) +
        "</code> <span class=\"muted\">" +
        escapeHtml(unit.state || "") +
        "</span></span></li>"
      );
    });

    if (live.probe) {
      var probe = live.probe;
      var probeText = probe.ok
        ? (probe.http_status ? "HTTP " + probe.http_status : "TCP 连接成功") +
          " · " +
          probe.latency_ms +
          " ms"
        : "失败" + (probe.error ? " · " + probe.error : "");
      rows.push(
        '<li class="meta-row"><span class="meta-key">探针</span><span class="meta-value">' +
          '<code>' +
          escapeHtml(probe.target || "") +
          "</code> " +
          pill(probe.ok ? "up" : "down") +
          ' <span class="muted">' +
          escapeHtml(probeText) +
          "</span></span></li>"
      );
    }

    if (service.tailscale) {
      var endpoints = (live.tailscale_endpoints || [])
        .map(function (endpoint) {
          return (
            "tcp:" +
            escapeHtml(String(endpoint.port)) +
            (endpoint.forward ? " → " + escapeHtml(endpoint.forward) : "")
          );
        })
        .join(" · ");
      rows.push(
        '<li class="meta-row"><span class="meta-key">Tailscale</span><span class="meta-value">' +
          '<code>svc:' +
          escapeHtml(service.tailscale.service) +
          "</code> " +
          pill(live.tailscale_served ? "up" : "degraded") +
          ' <span class="muted">' +
          (live.tailscale_served
            ? "本机已配置端点" + (endpoints ? " · " + endpoints : "")
            : "本机未配置端点") +
          "</span></span></li>"
      );

      if (live.tailscale_dns !== null && live.tailscale_dns !== undefined) {
        rows.push(
          '<li class="meta-row"><span class="meta-key">tailnet DNS</span><span class="meta-value">' +
            pill(live.tailscale_dns ? "up" : "unknown") +
            ' <span class="muted">' +
            (live.tailscale_dns
              ? escapeHtml(
                  service.tailscale.service + "." + (tailnetSuffix() || "<tailnet>.ts.net")
                ) + " 已解析"
              : "域名未解析：Service 可能尚未在 Tailscale 管理端定义或审批主机") +
            "</span></span></li>"
        );
      }
    }

    if (service.ports) {
      rows.push(
        '<li class="meta-row"><span class="meta-key">端口</span><span class="meta-value">' +
          service.ports
            .map(function (port) {
              return (
                "<code>" +
                escapeHtml(String(port.port)) +
                "</code> " +
                escapeHtml(port.role || "") +
                ' <span class="muted">' +
                escapeHtml(port.bind || "") +
                "</span>"
              );
            })
            .join(" · ") +
          "</span></li>"
      );
    }

    if (service.dataPaths && service.dataPaths.length) {
      rows.push(
        '<li class="meta-row"><span class="meta-key">数据</span><span class="meta-value">' +
          service.dataPaths
            .map(function (path) {
              return "<code>" + escapeHtml(path) + "</code>";
            })
            .join(" ") +
          "</span></li>"
      );
    }

    if (service.dependsOn && service.dependsOn.length) {
      rows.push(
        '<li class="meta-row"><span class="meta-key">依赖</span><span class="meta-value">' +
          service.dependsOn
            .map(function (id) {
              return '<span class="tag">' + escapeHtml(id) + "</span>";
            })
            .join(" ") +
          "</span></li>"
      );
    }

    var links = tailscaleLinks(service).concat(directLinks(service)).concat(publicLinks(service));

    var reasons = (live.reasons || []).length
      ? '<ul class="reasons">' +
        live.reasons
          .map(function (reason) {
            return "<li>" + escapeHtml(reason) + "</li>";
          })
          .join("") +
        "</ul>"
      : "";

    var notes = (service.notes || []).length
      ? '<ul class="notes notes-tight">' +
        service.notes
          .map(function (note) {
            return "<li class=\"note\">" + escapeHtml(note) + "</li>";
          })
          .join("") +
        "</ul>"
      : "";

    var tags = (service.tags || []).length
      ? '<div class="tags">' +
        service.tags
          .map(function (tag) {
            return '<span class="tag">' + escapeHtml(tag) + "</span>";
          })
          .join("") +
        "</div>"
      : "";

    return [
      '<article class="service" data-service="' + escapeHtml(service.id) + '">',
      '<div class="service-head">',
      '<div class="service-title">' +
        pill(live.state || "unknown") +
        "<h4>" +
        escapeHtml(service.name) +
        "</h4></div>",
      tags,
      "</div>",
      '<p class="service-summary">' + escapeHtml(service.summary || "") + "</p>",
      service.details ? '<p class="service-details muted">' + escapeHtml(service.details) + "</p>" : "",
      reasons,
      '<ul class="meta">' + unitRows.join("") + extraRows.join("") + rows.join("") + "</ul>",
      links.length ? '<div class="entries">' + links.join("") + "</div>" : "",
      notes,
      docButton(service) ? '<div class="panel-actions">' + docButton(service) + "</div>" : "",
      "</article>",
    ].join("");
  }

  function renderDeployment() {
    $("deployment-rows").innerHTML = DEPLOYMENT_ROWS.map(function (row) {
      var cells = row
        .map(function (cell, index) {
          return index === 0
            ? '<th scope="row">' + escapeHtml(cell) + "</th>"
            : "<td>" + escapeHtml(cell) + "</td>";
        })
        .join("");
      return "<tr>" + cells + "</tr>";
    }).join("");

    var summary = state.inventory.guide || {};
    $("deployment-summary").innerHTML =
      "<strong>结论：</strong>状态门户部署在本机并通过 Tailscale Service 暴露。" +
      "Cloudflare Pages 无法访问 tailnet 地址，" +
      "因此它只能承载不含实时状态的静态引导页。" +
      (summary.summary ? "" : "");
  }

  function renderFleet() {
    var fleet = state.status.fleet || {};
    if (!fleet.enabled) {
      $("fleet-panel").hidden = true;
      return;
    }
    $("fleet-panel").hidden = false;

    var config = state.inventory.fleet || {};

    if (!fleet.available) {
      $("fleet-note").textContent =
        "机群视图当前不可用：" + (fleet.reason || "未知原因");
      $("fleet-cards").innerHTML =
        '<div class="banner banner-warn">无法从 OpenObserve 读取机群指标。' +
        "本机的服务器与服务状态不受影响，它们来自本地探针。</div>";
      $("fleet-notes").innerHTML = "";
      return;
    }

    $("fleet-note").textContent = config.summary || "";
    $("fleet-cards").innerHTML = fleet.hosts
      .map(function (host) {
        var tone = host.reporting ? "up" : "degraded";
        return card(
          host.host_name + (host.local ? "（本机）" : ""),
          host.load1 === null || host.load1 === undefined ? "—" : host.load1.toFixed(2),
          "负载 1 分钟 · 内存已用 " +
            fmtBytes(host.memory_used_bytes) +
            " · " +
            (host.reporting
              ? "上报于 " + fmtAge(host.last_seen_age_seconds)
              : "最近上报 " + fmtAge(host.last_seen_age_seconds)),
          "",
          tone
        );
      })
      .join("");

    $("fleet-notes").innerHTML = (config.notes || [])
      .map(function (note) {
        return '<li class="note">' + escapeHtml(note) + "</li>";
      })
      .join("");
  }

  function renderStack() {
    var site = state.inventory.site || {};
    $("site-title").textContent = site.title || "Home Lab Portal";
    $("site-subtitle").textContent = site.subtitle || "";
    document.title = site.title || "Home Lab Portal";

    $("stack-note").textContent = site.intro || "";
    var notes = [
      "模块 modules/host-services/homelab-portal.nix 定义单元；config/homelab/inventory.json 是服务清单的唯一来源。",
      "清单变化会改变 store 路径，Home Manager 的 sd-switch 因此重启单元。",
      "访问边界是 tailnet：服务绑定 Tailscale 地址，不监听局域网，也没有公网入口。",
      "本页只读；所有部署变更仍然走仓库里的 Nix 模块和 just apply。",
    ];
    $("stack-notes").innerHTML = notes
      .map(function (note) {
        return '<li class="note">' + escapeHtml(note) + "</li>";
      })
      .join("");
  }

  // ---------------------------------------------------------------- reader

  function openDoc(name) {
    var panel = $("reader-panel");
    panel.hidden = false;
    $("reader-heading").textContent = name;
    $("reader-content").innerHTML = '<p class="muted">正在加载…</p>';

    fetch("/api/docs/" + encodeURIComponent(name), { cache: "no-store" })
      .then(function (response) {
        if (!response.ok) throw new Error("HTTP " + response.status);
        return response.text();
      })
      .then(function (markdown) {
        $("reader-content").innerHTML = window.renderMarkdown(markdown);
        panel.scrollIntoView({ behavior: "smooth", block: "start" });
      })
      .catch(function (error) {
        $("reader-content").innerHTML =
          '<p class="muted">无法加载文档：' + escapeHtml(error.message) + "</p>";
      });
  }

  // ----------------------------------------------------------------- fetch

  function setError(message) {
    var banner = $("load-error");
    if (!message) {
      banner.hidden = true;
      banner.textContent = "";
      return;
    }
    banner.hidden = false;
    banner.textContent = message;
  }

  function loadInventory() {
    return fetch("/api/inventory", { cache: "no-store" })
      .then(function (response) {
        if (!response.ok) throw new Error("HTTP " + response.status);
        return response.json();
      })
      .then(function (payload) {
        state.inventory = payload.inventory;
        state.docs = payload.docs || [];
        renderGuide();
        renderFilters();
        renderDeployment();
        renderStack();
      });
  }

  function loadStatus() {
    return fetch("/api/status", { cache: "no-store" })
      .then(function (response) {
        if (!response.ok) throw new Error("HTTP " + response.status);
        return response.json();
      })
      .then(function (payload) {
        state.status = payload;
        state.failures = 0;
        setError("");
        renderOverview();
        renderServices();
        renderFleet();
        $("last-updated").textContent =
          "更新于 " +
          new Date(payload.generated_at * 1000).toLocaleTimeString() +
          " · 采集耗时 " +
          payload.duration_ms +
          " ms";
      })
      .catch(function (error) {
        state.failures += 1;
        setError(
          "状态接口暂时不可用（" +
            error.message +
            "）。已连续失败 " +
            state.failures +
            " 次；下方数据可能是上次成功的结果。"
        );
        $("last-updated").textContent = "更新失败";
      });
  }

  function refresh() {
    var tasks = [loadStatus()];
    if (!state.inventory) tasks.push(loadInventory());
    return Promise.all(tasks);
  }

  function configureTimer() {
    if (state.timer) {
      window.clearInterval(state.timer);
      state.timer = null;
    }
    if ($("auto-refresh").checked && state.inventory) {
      var seconds = (state.inventory.site || {}).refreshSeconds || 15;
      state.timer = window.setInterval(loadStatus, seconds * 1000);
    }
  }

  function bindEvents() {
    $("refresh").addEventListener("click", function () {
      refresh().then(configureTimer);
    });

    $("auto-refresh").addEventListener("change", configureTimer);

    $("reader-close").addEventListener("click", function () {
      $("reader-panel").hidden = true;
    });

    $("service-filters").addEventListener("click", function (event) {
      var button = event.target.closest("[data-category]");
      if (!button) return;
      state.activeCategory = button.getAttribute("data-category");
      renderFilters();
      renderServices();
    });

    document.addEventListener("click", function (event) {
      var button = event.target.closest("[data-doc]");
      if (button) openDoc(button.getAttribute("data-doc"));
    });

    document.addEventListener("visibilitychange", function () {
      if (!document.hidden) loadStatus();
    });
  }

  function init() {
    bindEvents();
    loadInventory()
      .then(loadStatus)
      .then(configureTimer)
      .catch(function (error) {
        setError("初始化失败：" + error.message);
        $("last-updated").textContent = "加载失败";
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
