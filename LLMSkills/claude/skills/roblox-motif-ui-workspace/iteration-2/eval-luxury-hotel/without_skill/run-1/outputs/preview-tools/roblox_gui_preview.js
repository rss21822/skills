// Minimal Roblox GUI layout emulator for previews (no Studio).
// Input: the JSON tree written by dump_menu.luau. Emulates UDim2 sizing/positioning, AnchorPoint,
// Rotation, ZIndex (Sibling), ClipsDescendants, UIPadding, UIListLayout, UIAspectRatioConstraint,
// UICorner, UIStroke (Border -> outer ring, Contextual text -> text outline), UIGradient (multiplies the
// element's own background AND text, like Roblox), RichText <font>/<b>/<i>/<br>.
// Fonts: Enum.Font.Bodoni is drawn with Accanthis ADF Std (the face Roblox ships as "Bodoni"),
// JosefinSans with Josefin Sans, Gotham with Montserrat. Japanese glyphs fall back to Noto Sans JP,
// as Roblox falls back to its CJK sans. This is an approximation of the renderer, not a pixel match.
(function () {
	"use strict";
	const CJK = "'Noto Sans JP','Yu Gothic','Meiryo',sans-serif";
	const FONTS = {
		Bodoni: ["'Accanthis ADF Std'", 400],
		Garamond: ["'EB Garamond'", 400],
		JosefinSans: ["'Josefin Sans'", 400],
		Gotham: ["'Montserrat'", 400], GothamMedium: ["'Montserrat'", 500],
		GothamBold: ["'Montserrat'", 700], GothamBlack: ["'Montserrat'", 900],
		BuilderSans: ["'Montserrat'", 400], BuilderSansMedium: ["'Montserrat'", 500],
		BuilderSansBold: ["'Montserrat'", 700], BuilderSansExtraBold: ["'Montserrat'", 800],
		SourceSans: ["'Segoe UI'", 400], SourceSansSemibold: ["'Segoe UI'", 600], SourceSansBold: ["'Segoe UI'", 700],
	};
	const GUI = new Set(["Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton",
		"ScrollingFrame", "CanvasGroup", "ViewportFrame"]);
	const TEXT = new Set(["TextLabel", "TextButton", "TextBox"]);

	const kids = (n) => (Array.isArray(n.children) ? n.children : Object.values(n.children || {}));
	const ud = (u, len) => (u ? u.s * len + u.o : 0);
	const c255 = (c) => [Math.round(c.r * 255), Math.round(c.g * 255), Math.round(c.b * 255)];
	const rgba = (c, a) => { const [r, g, b] = Array.isArray(c) ? c : c255(c); return `rgba(${r},${g},${b},${Math.max(0, Math.min(1, a)).toFixed(3)})`; };
	const en = (v, d) => (v && v.v) || d;

	function fontOf(p) {
		const f = en(p.Font, "SourceSans");
		const [fam, w] = FONTS[f] || ["'Segoe UI'", 400];
		return { family: fam + "," + CJK, weight: w };
	}

	// Sample a ColorSequence / NumberSequence at time t.
	function sampleColor(seq, t) {
		if (!seq) return [1, 1, 1];
		const k = seq.k;
		for (let i = 0; i < k.length - 1; i++) {
			if (t >= k[i][0] && t <= k[i + 1][0]) {
				const f = (t - k[i][0]) / Math.max(1e-6, k[i + 1][0] - k[i][0]);
				return [1, 2, 3].map((j) => k[i][j] + (k[i + 1][j] - k[i][j]) * f);
			}
		}
		return k[k.length - 1].slice(1);
	}
	function sampleNumber(seq, t) {
		if (!seq) return 0;
		const k = seq.k;
		for (let i = 0; i < k.length - 1; i++) {
			if (t >= k[i][0] && t <= k[i + 1][0]) {
				const f = (t - k[i][0]) / Math.max(1e-6, k[i + 1][0] - k[i][0]);
				return k[i][1] + (k[i + 1][1] - k[i][1]) * f;
			}
		}
		return k[k.length - 1][1];
	}
	// CSS gradient for base colour * UIGradient, alpha = (1 - baseTransparency) * (1 - gradientTransparency).
	function gradientCss(g, baseColor, baseTransparency) {
		const p = g.props;
		const times = new Set([0, 1]);
		if (p.Color) p.Color.k.forEach((k) => times.add(k[0]));
		if (p.Transparency) p.Transparency.k.forEach((k) => times.add(k[0]));
		for (let i = 1; i < 10; i++) times.add(i / 10);
		const offset = p.Offset ? p.Offset.x : 0;
		const stops = [...times].sort((a, b) => a - b).map((t) => {
			const src = Math.max(0, Math.min(1, t - offset));
			const gc = sampleColor(p.Color, src);
			const gt = sampleNumber(p.Transparency, src);
			const col = [baseColor.r * gc[0], baseColor.g * gc[1], baseColor.b * gc[2]].map((v) => Math.round(v * 255));
			return `${rgba(col, (1 - baseTransparency) * (1 - gt))} ${(t * 100).toFixed(1)}%`;
		});
		return `linear-gradient(${(p.Rotation || 0) + 90}deg, ${stops.join(", ")})`;
	}

	function richToHtml(text) {
		return text
			.replace(/<br\s*\/?>/gi, "<br>")
			.replace(/<font([^>]*)>/gi, (_, attrs) => {
				let style = "";
				const color = /color\s*=\s*["']([^"']+)["']/i.exec(attrs);
				if (color) {
					const c = color[1].trim();
					const m = /^rgb\((\d+),\s*(\d+),\s*(\d+)\)$/i.exec(c);
					style += `color:${m ? `rgb(${m[1]},${m[2]},${m[3]})` : c};`;
				}
				const size = /size\s*=\s*["'](\d+)["']/i.exec(attrs);
				if (size) style += `font-size:${size[1]}px;`;
				const tr = /transparency\s*=\s*["']([\d.]+)["']/i.exec(attrs);
				if (tr) style += `opacity:${1 - parseFloat(tr[1])};`;
				return `<span style="${style}">`;
			})
			.replace(/<\/font>/gi, "</span>");
	}
	const escapeHtml = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

	function sizeOf(c, pw, ph) {
		const s = c.props.Size || { xs: 0, xo: 100, ys: 0, yo: 100 };
		let w = s.xs * pw + s.xo, h = s.ys * ph + s.yo;
		const ar = kids(c).find((k) => k.cls === "UIAspectRatioConstraint");
		if (ar) {
			const r = ar.props.AspectRatio || 1;
			if (en(ar.props.AspectType, "FitWithinMaxSize") === "FitWithinMaxSize") {
				if (w / h > r) w = h * r; else h = w / r;
			} else if (en(ar.props.DominantAxis, "Width") === "Width") h = w / r; else w = h * r;
		}
		return { w: Math.max(0, w), h: Math.max(0, h) };
	}

	function layoutChildren(n, el, w, h, ctx) {
		const ch = kids(n);
		const pad = ch.find((c) => c.cls === "UIPadding");
		const pl = pad ? ud(pad.props.PaddingLeft, w) : 0, pr = pad ? ud(pad.props.PaddingRight, w) : 0;
		const pt = pad ? ud(pad.props.PaddingTop, h) : 0, pb = pad ? ud(pad.props.PaddingBottom, h) : 0;
		const cw = w - pl - pr, chh = h - pt - pb;
		const list = ch.find((c) => c.cls === "UIListLayout");
		let guis = ch.filter((c) => GUI.has(c.cls) && c.props.Visible !== false);
		let bottom = 0;
		if (list) {
			const lp = list.props;
			guis = guis.map((c, i) => ({ c, i })).sort((a, b) => {
				if (en(lp.SortOrder, "LayoutOrder") === "Name") return a.c.name < b.c.name ? -1 : a.c.name > b.c.name ? 1 : a.i - b.i;
				return ((a.c.props.LayoutOrder || 0) - (b.c.props.LayoutOrder || 0)) || (a.i - b.i);
			}).map((x) => x.c);
			const horizontal = en(lp.FillDirection, "Vertical") === "Horizontal";
			const gap = ud(lp.Padding, horizontal ? cw : chh);
			const sizes = guis.map((c) => sizeOf(c, cw, chh));
			const total = sizes.reduce((a, s) => a + (horizontal ? s.w : s.h), 0) + gap * Math.max(0, guis.length - 1);
			const ha = en(lp.HorizontalAlignment, "Left"), va = en(lp.VerticalAlignment, "Top");
			let cursor = horizontal
				? (ha === "Center" ? (cw - total) / 2 : ha === "Right" ? cw - total : 0)
				: (va === "Center" ? (chh - total) / 2 : va === "Bottom" ? chh - total : 0);
			guis.forEach((c, i) => {
				const s = sizes[i];
				let x, y;
				if (horizontal) {
					x = cursor; cursor += s.w + gap;
					y = va === "Center" ? (chh - s.h) / 2 : va === "Bottom" ? chh - s.h : 0;
				} else {
					y = cursor; cursor += s.h + gap;
					x = ha === "Center" ? (cw - s.w) / 2 : ha === "Right" ? cw - s.w : 0;
				}
				bottom = Math.max(bottom, pt + y + s.h);
				renderNode(c, el, { x: pl + x, y: pt + y, w: s.w, h: s.h }, ctx);
			});
		} else {
			guis.forEach((c) => {
				const s = sizeOf(c, cw, chh);
				const pos = c.props.Position || { xs: 0, xo: 0, ys: 0, yo: 0 };
				const ap = c.props.AnchorPoint || { x: 0, y: 0 };
				const x = pos.xs * cw + pos.xo - ap.x * s.w, y = pos.ys * chh + pos.yo - ap.y * s.h;
				bottom = Math.max(bottom, pt + y + s.h);
				renderNode(c, el, { x: pl + x, y: pt + y, w: s.w, h: s.h }, ctx);
			});
		}
		return { bottom, pad: { pl, pr, pt, pb } };
	}

	function renderNode(n, parentEl, r, ctx) {
		const p = n.props;
		const el = document.createElement("div");
		el.className = "rbx rbx-" + n.cls;
		el.dataset.name = n.name;
		el.title = n.name;
		const st = el.style;
		st.position = "absolute";
		st.left = r.x + "px"; st.top = r.y + "px"; st.width = r.w + "px"; st.height = r.h + "px";
		st.boxSizing = "border-box";
		st.zIndex = String(p.ZIndex == null ? 1 : p.ZIndex);
		if (p.Rotation) st.transform = `rotate(${p.Rotation}deg)`;
		if (p.ClipsDescendants || n.cls === "ScrollingFrame") st.overflow = "hidden";

		const mods = kids(n);
		const corner = mods.find((m) => m.cls === "UICorner");
		const strokes = mods.filter((m) => m.cls === "UIStroke" && m.props.Enabled !== false);
		const grad = mods.find((m) => m.cls === "UIGradient" && m.props.Enabled !== false);
		const isText = TEXT.has(n.cls);
		if (corner) {
			const cr = corner.props.CornerRadius || { s: 0, o: 8 };
			st.borderRadius = Math.min(ud(cr, Math.min(r.w, r.h)), Math.min(r.w, r.h) / 2) + "px";
		}
		const bt = p.BackgroundTransparency == null ? 0 : p.BackgroundTransparency;
		const bg = p.BackgroundColor3 || { r: 1, g: 1, b: 1 };
		if (bt < 1) {
			if (grad) st.backgroundImage = gradientCss(grad, bg, bt);
			else st.backgroundColor = rgba(bg, 1 - bt);
		}
		const shadows = [];
		let textShadow = null;
		strokes.forEach((s) => {
			const sp = s.props;
			const mode = en(sp.ApplyStrokeMode, "Contextual");
			const col = rgba(sp.Color || { r: 0, g: 0, b: 0 }, 1 - (sp.Transparency || 0));
			const t = sp.Thickness == null ? 1 : sp.Thickness;
			if (mode === "Contextual" && isText) {
				textShadow = [[-1, 0], [1, 0], [0, -1], [0, 1], [-1, -1], [1, 1], [-1, 1], [1, -1]]
					.map(([dx, dy]) => `${dx * t}px ${dy * t}px 0 ${col}`).join(",");
			} else {
				shadows.push(`0 0 0 ${t}px ${col}`);
			}
		});
		if (!corner && !strokes.length && (p.BorderSizePixel || 0) > 0 && bt < 1) {
			shadows.push(`0 0 0 ${p.BorderSizePixel}px ${rgba(p.BorderColor3 || { r: 27 / 255, g: 42 / 255, b: 53 / 255 }, 1 - bt)}`);
		}
		if (shadows.length) st.boxShadow = shadows.join(",");
		parentEl.appendChild(el);

		const layout = layoutChildren(n, el, r.w, r.h, ctx);

		if (isText && p.Text != null && p.Text !== "") {
			const t = document.createElement("div");
			const ts = t.style;
			const pad = layout.pad;
			ts.position = "absolute";
			ts.left = pad.pl + "px"; ts.right = pad.pr + "px"; ts.top = pad.pt + "px"; ts.bottom = pad.pb + "px";
			ts.display = "flex";
			const xa = en(p.TextXAlignment, "Center"), ya = en(p.TextYAlignment, "Center");
			ts.justifyContent = xa === "Left" ? "flex-start" : xa === "Right" ? "flex-end" : "center";
			ts.alignItems = ya === "Top" ? "flex-start" : ya === "Bottom" ? "flex-end" : "center";
			ts.textAlign = xa.toLowerCase() === "center" ? "center" : xa.toLowerCase();
			const f = fontOf(p);
			ts.fontFamily = f.family; ts.fontWeight = String(f.weight);
			let size = p.TextSize || 14;
			if (p.TextScaled) size = Math.min(r.h * 0.8, 100);
			ts.fontSize = size + "px";
			ts.lineHeight = String(1.15 * (p.LineHeight || 1));
			ts.whiteSpace = p.TextWrapped ? "pre-wrap" : "pre";
			ts.zIndex = "0";
			ts.pointerEvents = "none";
			const tc = p.TextColor3 || { r: 0, g: 0, b: 0 };
			const tt = p.TextTransparency || 0;
			ts.color = rgba(tc, 1 - tt);
			if (textShadow) ts.textShadow = textShadow;
			const span = document.createElement("span");
			span.innerHTML = p.RichText ? richToHtml(p.Text) : escapeHtml(p.Text);
			if (grad) {
				span.style.backgroundImage = gradientCss(grad, tc, tt);
				span.style.webkitBackgroundClip = "text";
				span.style.backgroundClip = "text";
				span.style.color = "transparent";
			}
			t.appendChild(span);
			el.insertBefore(t, el.firstChild);
		}

		if (n.cls === "ScrollingFrame" && layout.bottom > r.h + 1) {
			const bar = document.createElement("div");
			const thick = p.ScrollBarThickness == null ? 12 : p.ScrollBarThickness;
			const bs = bar.style;
			bs.position = "absolute"; bs.right = "0px"; bs.top = "0px"; bs.width = thick + "px";
			bs.height = (r.h * r.h / layout.bottom) + "px"; bs.zIndex = "999";
			bs.background = rgba(p.ScrollBarImageColor3 || { r: 0, g: 0, b: 0 }, 1 - (p.ScrollBarImageTransparency || 0));
			el.appendChild(bar);
		}
		return el;
	}

	// Render a ScreenGui dump into `stage` (a positioned element sized to the viewport).
	window.renderRobloxGui = function (stage, root, viewport) {
		const w = viewport[0], h = viewport[1];
		const inset = root.props.IgnoreGuiInset ? 0 : 58;
		const holder = document.createElement("div");
		holder.style.position = "absolute";
		holder.style.left = "0px"; holder.style.top = inset + "px";
		holder.style.width = w + "px"; holder.style.height = (h - inset) + "px";
		stage.appendChild(holder);
		layoutChildren(root, holder, w, h - inset, {});
	};
})();
