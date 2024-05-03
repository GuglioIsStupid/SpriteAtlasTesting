local class = require("class")
local json = require("json")
local FlxAnimate = class:extend()

function string:split(sep)
    local sep, fields = sep or ":", {}
    local pattern = string.format("([^%s]+)", sep)
    self:gsub(pattern, function(c) fields[#fields + 1] = c end)
    return fields
end

-- table.inflate, the second argument is the size of the table
function table.inflate(t, size)
    while #t < size do
        table.insert(t, 0)
    end
    return t
end

function FlxAnimate:new(x, y, path)
    self.anim = nil
    self.showPivot = false
    self._pivot = {}
    self.x = x
    self.y = y
    self.alpha = 1
    -- the matrix has 14 fields.
    self._matrix = {1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0}
    self.quads = {}
    self.graphic = nil
    self:loadAtlas(path)
end

function FlxAnimate:loadAtlas(path)
    -- read json file (path/Animation.json). Remove unicode characters from start
    local jsondata = json.decode(love.filesystem.read(path .. "/Animation.json"):gsub("^%z+", ""))
    self.anim = self:_loadAtlas(jsondata)
    local spritemapjson = json.decode(love.filesystem.read(path .. "/spritemap1.json"):gsub("[\239\187\191]", ""))
    self.frames = self:_loadFrames(spritemapjson)
    self.graphic = love.graphics.newImage(path .. "/spritemap1.png")
end

function FlxAnimate:_loadAtlas(json)
    local anim ={}
    anim.symbolDictionary = {}
    anim.stageInstance = nil

    anim.symbolDictionary = self:setSymbols(json)
    
    --		stageInstance = (animationFile.AN.STI != null) ? FlxElement.fromJSON(cast animationFile.AN.STI) : new FlxElement(new SymbolParameters(animationFile.AN.SN));
    anim.stageInstance = json.AN.STI ~= nil and self:elementFromJSON(json.AN.STI) or self:newElement(self:newSymbolParameters(json.AN.SN))

    anim.curInstance = anim.stageInstance

    anim.curFrame = anim.stageInstance.symbol.firstFrame
    
    anim._parent = {}
    anim._parent.origin = anim.stageInstance.symbol.transformationPoint
    --anim.metadata = self:metadata(json.AN.N, json.MD.FRT)
    return anim
end

function FlxAnimate:setSymbols(anim)
    local symbols = {}
    symbols[anim.AN.SN] = self:newSymbol(anim.AN.SN, self:timelineFromJSON(anim.AN.TL))
    if anim.SD ~= nil then
        for _, symbol in ipairs(anim.SD.S) do
            symbols[symbol.SN] = self:newSymbol(symbol.SN, self:timelineFromJSON(symbol.TL))
        end
    end
    return symbols
end

function FlxAnimate:newSymbol(name, timeline)
    local symbol = {}
    symbol.layers = {}
    symbol.curFrame = 1
    symbol.timeline = timeline
    symbol.name = name

    return symbol
end

function FlxAnimate:timelineFromJSON(timeline)
    if (not timeline or not timeline.L) then return nil end
    local layers = {}
    for _, layer in ipairs(timeline.L) do
        table.insert(layers, self:layerFromJSON(layer))
    end

    return layers
end

function FlxAnimate:elementFromJSON(json)
end

function FlxAnimate:newElement(bitmap, symbol, matrix)
    local element = {}
    element.bitmap = bitmap
    element.symbol = symbol
    element.matrix = matrix
    return element
end

function FlxAnimate:newSymbolParameters(name, instance, type, loop)
    local params = {}
    params.name = name or ""
    params.instance = instance or ""
    params.type = type or "Graphic"
    params.loop = loop or "Loop"
    params.firstFrame = 1
    params.transformationPoint = {x = 0, y = 0}
    return params
end

function FlxAnimate:layerFromJSON(json)
    if not json then return nil end
    local frames = {}
    local l = self:newLayer(json.LN)
    if (json.LT or json.Clpb) then
        --            l.type = (layer.LT != null) ? Clipper : Clipped(layer.Clpb); 
        l.type = json.LT ~= nil and "Clipper" or "Clipped"
    end
    if json.FR then
        for _, frame in ipairs(json.FR) do
            table.insert(frames, self:keyFrameFromJSON(frame))
        end
    end
    
    return l
end

function FlxAnimate:newLayer(name, keyframes)
    local layer = {}
    layer.name = name
    layer.keyframes = keyframes or {}
    layer.visible = true
    layer._labels = {}
    return layer
end

function FlxAnimate:keyFrameFromJSON(json)
    if not json then return nil end
    local elements = {}
    if json.E then
        for _, element in ipairs(json.E) do
            table.insert(elements, self:elementFromJSON(element))
        end
    end
    return elements
end

function FlxAnimate:elementFromJSON(json)
    local symbol = json.SI ~= nil
    local params = nil
    if symbol then
        params = self:newSymbolParameters()
        params.instance = json.SI.IN
        params.type = json.SI.ST == "movieclip" and "MovieClip" or json.SI.ST == "button" and "Button" or "Graphic"
        local lp = json.SI.LP == nil and "loop" or json.SI.LP:split("R")[0]
        params.loop = lp == "playonce" and "PlayOnce" or lp == "singleframe" and "SingleFrame" or "Loop"
        params.reverse = json.SI.LP == nil and false or string.find(json.SI.LP or "", "R") ~= nil
        params.firstFrame = (json.SI.FF or 0)+1
        params.colorEffect = nil--self:colorEffectFromJSON(json.SI.C)
        params.name = json.SI.SN
        params.transformationPoint = {x = json.SI.TRP.x, y = json.SI.TRP.y}
    end

    local m3d = symbol and json.SI.M3D or json.ASI.M3D
    local m = {}
    if type(m3d) == "table" then
        m = {1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0}
    else
        for _, field in ipairs(self.matrixNames) do
            table.insert(m, m3d[field])
        end
    end

    if not symbol and m3d == nil then
        m[1], m[4] = 1, 1
        m[2], m[3], m[5], m[6] = 0, 0, 0, 0
    end

    local pos = symbol and json.SI.bitmap and json.SI.bitmap.POS or json.ASI and json.ASI.POS
    if pos == nil then
        pos = {x = 0, y = 0}
    end

    -- just make a normal matrix, no FlxMatrix
    return self:newElement(symbol and json.SI and json.SI.bitmap, params, m)
end

function FlxAnimate:_loadFrames(json)
    local frames = {}
    for _, frame in ipairs(json.ATLAS.SPRITES) do
        -- has name, x, y, w, h, rotated
        table.insert(frames, self:newFrame(frame.SPRITE, json.meta.size))
    end
    return frames
end

function FlxAnimate:newFrame(json, size)
    local frame = {}
    frame.name = json.name
    frame.x = json.x
    frame.y = json.y
    frame.w = json.w
    frame.h = json.h
    frame.rotated = json.rotated

    table.insert(self.quads, love.graphics.newQuad(frame.x, frame.y, frame.w, frame.h, size.w, size.h))

    return frame
end

function FlxAnimate:parseElement(instance, curFrame, matrix, colorTransform, mainSymbol)
    local mainSymbol = mainSymbol == nil and false or mainSymbol
    local matrix = matrix or {1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0}

    if not instance.bitmap then
        self:drawLimb(self.frames[instance.bitmap], self._matrix, colorTransform)
    end

    local symbol = self.anim.symbolDictionary[instance.symbol.name]
    local firstFrame = (symbol.firstFrame or 1) + (curFrame or 0)
    firstFrame = firstFrame > #symbol.timeline and #symbol and firstFrame or 1

    local layers = symbol.timeline
    print(#layers)
    for _, layer in ipairs(layers) do
        if layer.visible then
            local keyframe = layer.keyframes[firstFrame]
            if keyframe then
                for _, element in ipairs(keyframe) do
                    self:parseElement(element, curFrame, matrix, colorTransform, false)
                end
            end
        end
    end
end

function FlxAnimate:draw()
    if self.alpha <= 0 then return end
    self:parseElement(self.anim.curInstance, self.anim.curFrame, self._matrix, self.colorTransform, true)
end

function FlxAnimate:drawLimb(frame, matrix, colorTransform)
    local quad = 1
    for _, f in ipairs(self.frames) do
        if f.name == frame then
            quad = f
            break
        end
    end
    
    --local rMatrix = love.math.newTransform():setMatrix(unpack(table.inflate(matrix, 16)))
    love.graphics.push()
    --manually set the matrix (no love.graphics.applyTransform)
    love.graphics.translate(self.x, self.y)
    
    love.graphics.setColor(1, 1, 1, self.alpha)
    love.graphics.draw(self.graphic, self.quads[quad], 0, 0)
    love.graphics.pop()
end

function love.load()
    spr = FlxAnimate(0, 0, "ninja")
end

function love.update(dt)

end

function love.draw()
    spr:draw()
end