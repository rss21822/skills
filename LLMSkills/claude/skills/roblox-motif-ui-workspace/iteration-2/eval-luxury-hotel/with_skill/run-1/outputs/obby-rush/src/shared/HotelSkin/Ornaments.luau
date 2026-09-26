-- Small drawing parts for the Grand Hotel skin: hairline gold double rules, corner diamonds,
-- coin tokens, crossed keys, straight segments. Everything is made of Frames (no image assets), is not Active
-- (never swallows clicks) and is named "Hotel..." so it cannot collide with the menu's names.
return function(kit)
	local P = kit.P
	local O = {}

	-- Instance.new defaults draw a 1 px dark border and a grey face: every part sets both.
	function O.new(className, parent, props)
		local object = Instance.new(className)
		pcall(function() object.BorderSizePixel = 0 end)
		if className == "Frame" or className == "TextLabel" then
			object.Active = false
		end
		if className == "TextLabel" then
			object.BackgroundTransparency = 1
			object.TextWrapped = false
		end
		for key, value in pairs(props or {}) do
			object[key] = value
		end
		object.Parent = parent
		return object
	end

	function O.frame(parent, props)
		return O.new("Frame", parent, props)
	end

	function O.label(parent, role, props)
		local label = O.new("TextLabel", parent, props)
		kit:setFont(label, role or "body")
		return label
	end

	function O.corner(object, radius)
		local corner = object:FindFirstChildOfClass("UICorner") or O.new("UICorner", object)
		corner.CornerRadius = radius or UDim.new(0, kit.shape.corner or 2)
		return corner
	end

	function O.round(object)
		return O.corner(object, UDim.new(1, 0))
	end

	-- Opaque hairline on the border (never the semi-transparent 1 px of the old theme).
	function O.stroke(object, color, thickness, name)
		local stroke = object:FindFirstChild(name or "HotelEdge") or O.new("UIStroke", object, {Name = name or "HotelEdge"})
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Color, stroke.Thickness, stroke.Transparency = color or P.gold, thickness or 1, 0
		return stroke
	end

	-- The inner line of a double rule: a transparent frame `inset` px inside the edge.
	function O.rule(object, inset, color, name)
		local rule = object:FindFirstChild(name or "HotelRule") or O.frame(object, {Name = name or "HotelRule"})
		rule.BackgroundTransparency = 1
		rule.AnchorPoint = Vector2.new(0.5, 0.5)
		rule.Position = UDim2.fromScale(0.5, 0.5)
		rule.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
		rule.ZIndex = object.ZIndex
		O.stroke(rule, color or P.goldDeep, 1, "HotelRuleLine")
		return rule
	end

	-- A lozenge: a square turned 45 degrees (Art Deco jewel, map pin of the double rule).
	function O.diamond(parent, size, color, props)
		local diamond = O.frame(parent, {
			Name = "HotelDiamond", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size),
			BackgroundColor3 = color or P.gold, Rotation = 45, ZIndex = parent.ZIndex,
		})
		for key, value in pairs(props or {}) do
			diamond[key] = value
		end
		return diamond
	end

	function O.cornerDiamonds(object, inset, size, color)
		for _, at in ipairs({{0, 0}, {1, 0}, {0, 1}, {1, 1}}) do
			O.diamond(object, size or 7, color, {
				Name = "HotelCornerDiamond",
				Position = UDim2.new(at[1], at[1] == 0 and inset or -inset, at[2], at[2] == 0 and inset or -inset),
			})
		end
	end

	-- Gold coin token (replaces the coin emoji, which Roblox draws as a tofu box).
	function O.coin(parent, size, props)
		local coin = O.frame(parent, {
			Name = "HotelCoin", Size = UDim2.fromOffset(size, size), AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = P.primary, ZIndex = parent.ZIndex,
		})
		O.round(coin)
		O.stroke(coin, P.goldLight, 1)
		local ring = O.frame(coin, {
			Name = "HotelCoinRing", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.6, 0.6), BackgroundTransparency = 1, ZIndex = coin.ZIndex,
		})
		O.round(ring)
		O.stroke(ring, P.goldDeep, 1)
		for key, value in pairs(props or {}) do
			coin[key] = value
		end
		return coin
	end

	-- A straight line between two offset points of `parent` (rotated thin frame).
	function O.segment(parent, x1, y1, x2, y2, thickness, color, transparency, name)
		local dx, dy = x2 - x1, y2 - y1
		local length = math.sqrt(dx * dx + dy * dy)
		return O.frame(parent, {
			Name = name or "HotelLine", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2),
			Size = UDim2.fromOffset(length + 0.5, thickness or 1), Rotation = math.deg(math.atan2(dy, dx)),
			BackgroundColor3 = color or P.gold, BackgroundTransparency = transparency or 0, ZIndex = parent.ZIndex,
		})
	end

	function O.circle(parent, cx, cy, diameter, color, transparency, name)
		local circle = O.frame(parent, {
			Name = name or "HotelDot", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy),
			Size = UDim2.fromOffset(diameter, diameter), BackgroundColor3 = color or P.gold,
			BackgroundTransparency = transparency or 0, ZIndex = parent.ZIndex,
		})
		O.round(circle)
		return circle
	end

	-- Horizontal hairline with a lozenge in the middle (section divider of a menu card).
	function O.divider(parent, props, color)
		local holder = O.frame(parent, {Name = "HotelDivider", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 9)})
		for key, value in pairs(props or {}) do
			holder[key] = value
		end
		O.frame(holder, {
			Name = "HotelDividerLine", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = color or P.gold, ZIndex = holder.ZIndex,
		})
		O.diamond(holder, 7, color or P.gold, {Position = UDim2.fromScale(0.5, 0.5)})
		return holder
	end

	-- A hotel key drawn along +X (bow ring on the left, bit on the right), turned by `rotation`
	-- about its centre. Two of them crossed are the concierge's golden keys.
	function O.key(parent, length, rotation, color, props)
		color = color or P.gold
		local key = O.frame(parent, {
			Name = "HotelKey", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromOffset(length, 12), BackgroundTransparency = 1, Rotation = rotation or 0, ZIndex = parent.ZIndex,
		})
		local bow = O.frame(key, {
			Name = "HotelKeyBow", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(9, 9), BackgroundTransparency = 1, ZIndex = key.ZIndex,
		})
		O.round(bow)
		O.stroke(bow, color, 1.5)
		O.frame(key, {Name = "HotelKeyShaft", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 9, 0.5, 0), Size = UDim2.new(1, -9, 0, 2), BackgroundColor3 = color, ZIndex = key.ZIndex})
		O.frame(key, {Name = "HotelKeyBit", Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(3, 5), BackgroundColor3 = color, ZIndex = key.ZIndex})
		O.frame(key, {Name = "HotelKeyBit", Position = UDim2.new(1, -9, 0.5, 0), Size = UDim2.fromOffset(3, 4), BackgroundColor3 = color, ZIndex = key.ZIndex})
		for k, v in pairs(props or {}) do
			key[k] = v
		end
		return key
	end

	-- Deterministic pseudo random (Park-Miller): the same veins on every client and in tests.
	function O.random(seed)
		local state = seed % 2147483647
		if state <= 0 then state += 2147483646 end
		return function(low, high)
			state = (state * 16807) % 2147483647
			local unit = (state - 1) / 2147483646
			return low + (high - low) * unit
		end
	end

	return O
end
