local transf = require "transf"
local vec4 = require "vec4"
local vec2 = require "snowball_farmer_vec2"
local vec3 = require "snowball_farmer_vec3"
local mat3 = require "snowball_farmer_mat3"
local poly = require "snowball_farmer_polygon"
local plan = require "snowball_farmer_planner"
local farmer = {}

farmer.markerStore = nil
farmer.finisherStore = nil
farmer.markerId = "asset/snowball_farmer_marker.mdl"
farmer.finisherId = "asset/snowball_farmer_finisher.mdl"

farmer.decorations = {
    {"decoration/snowball_farmer_grass_1.mdl", "decoration/snowball_farmer_grass_2.mdl"},
    {
        "decoration/snowball_farmer_fruiter_1.mdl",
        "decoration/snowball_farmer_fruiter_2.mdl",
        "decoration/snowball_farmer_fruiter_3.mdl"
    }
}

farmer.fences = {
    {
        name = "snowball_farmer_fence_wood",
        id_post = "asset/snowball_farmer_fences/wood_post.mdl",
        id_middle = "asset/snowball_farmer_fences/wood_middle.mdl",
        length = 3.0
    },
    {
        name = "snowball_farmer_fence_metal",
        id_post = "asset/snowball_farmer_fences/metal_post.mdl",
        id_middle = "asset/snowball_farmer_fences/metal_middle.mdl",
        length = 2.8
    },
    {
        name = "snowball_farmer_fence_cow",
        id_post = "asset/snowball_farmer_fences/cow_post.mdl",
        id_middle = "asset/snowball_farmer_fences/cow_middle.mdl",
        length = 2.11874
    }
}

function farmer.updateMarkers()
    if not farmer.markerStore then
        farmer.markerStore = {}
    end
    if not farmer.finisherStore then
        farmer.finisherStore = {}
    end

    return plan.updateEntityLists(farmer.markerId, farmer.markerStore, farmer.finisherId, farmer.finisherStore)
end

function farmer.getPolygon(markers)
    local polygon = {}

    for i = 1, #markers do
        local marker = markers[i]
        polygon[#polygon + 1] = {marker.position[1], marker.position[2], marker.position[3]}
    end

    if #polygon == 0 then
        return nil
    end

    return polygon
end

function farmer.isInBounds(point, bounds)
    if
        (point[1] < bounds.x or point[1] > bounds.x + bounds.width or point[2] < bounds.y or
            point[2] > bounds.y + bounds.height)
     then
        return false
    else
        return true
    end
end

function farmer.addDecoration(x, y, transforms, tile_size, bounds)
    local height = game.interface.getHeight({x, y})
    if (height >= 100) then
        local transform = transf.rotZTransl(math.random() * math.pi * 2.0, {x = x, y = y, z = height})

        local cellx = tostring(math.floor(x / tile_size - bounds.x))
        local celly = tostring(math.floor(y / tile_size - bounds.y))

        if not transforms[cellx] then
            transforms[cellx] = {}
        end

        if not transforms[cellx][celly] then
            transforms[cellx][celly] = {}
        end

        transforms[cellx][celly][#(transforms[cellx][celly]) + 1] = transform
    end
end

function farmer.distributeRandomly(plantpoly, density)
    local transforms = {}

    local bounds = poly.getBounds(plantpoly)
    local decoDensity = 1.0 / density
    local tileSize = density * 2

    local area = bounds.width * bounds.height
    if not area or area < 1e-6 then
        return transforms
    end

    local numDecos = math.max(1, math.floor(decoDensity * area))
    local transforms = {}

    for k = 1, numDecos do
        local x = math.random() * bounds.width + bounds.x
        local y = math.random() * bounds.height + bounds.y

        local plant = poly.contains(plantpoly, {x, y}, bounds)

        if plant then
            farmer.addDecoration(x, y, transforms, tileSize, bounds)
        end
    end

    return transforms
end

function farmer.intersection(p1, r1, p2, r2)
    local a11 = r1[1]
    local a12 = -r2[1]
    local a21 = r1[2]
    local a22 = -r2[2]
    local b1 = p2[1] - p1[1]
    local b2 = p2[2] - p1[2]

    local n = a11 * a22 - a21 * a12
    if n == 0 then
        return nil
    end

    local s = (b1 * a22 - b2 * a12) / n
    return {p1[1] + s * r1[1], p1[2] + s * r1[2]}
end

function farmer.distributeInRows(plantpoly, density)
    local transforms = {}

    local distanceOfRows = density
    local distanceInRow = density / 2
    local tileSize = density * 2
    local bounds = poly.getBounds(plantpoly)
    local d = vec2.normalize(vec2.sub(plantpoly[2], plantpoly[1]))

    if d[1] < 0 then
        d = vec2.mul(-1, d)
    end

    local starts = {}
    if d[2] > 0 then
        x = bounds.x
        y = bounds.y + bounds.height

        while y > bounds.y do
            starts[#starts + 1] = {x, y}
            y = y - (1 / d[1]) * distanceOfRows
        end

        local intersection =
            farmer.intersection(
            vec2.add(starts[#starts], vec2.mul(distanceOfRows, {d[2], -d[1]})),
            d,
            {bounds.x, bounds.y},
            {1, 0}
        )

        if intersection then
            x = intersection[1]
            y = intersection[2]

            while x < bounds.x + bounds.width do
                starts[#starts + 1] = {x, y}
                x = x + 1 / d[2] * distanceOfRows
            end
        end
    else
        x = bounds.x
        y = bounds.y

        while y < bounds.y + bounds.height do
            starts[#starts + 1] = {x, y}
            y = y + (1 / d[1]) * distanceOfRows
        end

        local intersection =
            farmer.intersection(
            vec2.add(starts[#starts], vec2.mul(distanceOfRows, {-d[2], d[1]})),
            d,
            {bounds.x, bounds.y + bounds.height},
            {1, 0}
        )

        if intersection then
            x = intersection[1]
            y = intersection[2]

            while x < bounds.x + bounds.width do
                starts[#starts + 1] = {x, y}
                x = x + 1 / math.abs(d[2]) * distanceOfRows
            end
        end
    end

    for i = 1, #starts do
        local point = starts[i]
        while farmer.isInBounds(point, bounds) do
            local plant = poly.contains(plantpoly, point, bounds)

            if plant then
                farmer.addDecoration(point[1], point[2], transforms, tileSize, bounds)
            end

            point = vec2.add(point, vec2.mul(distanceInRow, d))
        end
    end

    return transforms
end

function farmer.decorate(plantpoly, decoration, density, distribution)
    local transforms = nil

    if (distribution == "random") then
        transforms = farmer.distributeRandomly(plantpoly, density)
    end

    if (distribution == "rows") then
        transforms = farmer.distributeInRows(plantpoly, density)
    end

    if transforms then
        for x, transformsx in pairs(transforms) do
            for y, transformsy in pairs(transformsx) do
                game.interface.buildConstruction(
                    "asset/snowball_farmer_patch.con",
                    {transforms = transformsy, decoration = decoration},
                    {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
                )
            end
        end
    end
end

function farmer.fenceSegment(a, b, center, fence, rotation, result)
    local length = fence.length

    a[3] = game.interface.getHeight({a[1] + center[1], a[2] + center[2]}) - center[3]
    b[3] = game.interface.getHeight({b[1] + center[1], b[2] + center[2]}) - center[3]

    local v = vec3.sub(b, a)
    local vn = vec3.mul(vec3.length(v) / length, vec3.normalize(v))
    local o = vec3.normalize({v[2], -v[1], 0.0})

    local affine = mat3.affine(vn, o)

    local transform =
        transf.new(
        vec4.new(affine[1][1], affine[2][1], affine[3][1], .0),
        vec4.new(affine[1][2], affine[2][2], affine[3][2], .0),
        vec4.new(affine[1][3], affine[2][3], affine[3][3], .0),
        vec4.new(a[1], a[2], a[3], 1.0)
    )

    result.models[#result.models + 1] = {
        id = fence.id_middle,
        transf = transform
    }

    result.models[#result.models + 1] = {
        id = fence.id_post,
        transf = transf.rotZTransl(rotation, {x = b[1], y = b[2], z = b[3]})
    }
end

function farmer.fence(plantpoly, center, fence, result)
    local length = fence.length

    --Calculate the correct rotation of fence posts for every segment, no matter the orientation of the polygon
    local rf = 1
    if poly.isClockwise(plantpoly) then
        rf = -1
    end
    h = game.interface.getHeight({plantpoly[1][1] + center[1], plantpoly[1][2] + center[2]}) - center[3]

    result.models[#result.models + 1] = {
        id = fence.id_post,
        transf = transf.rotZTransl(
            math.atan2(rf * (plantpoly[2][2] - plantpoly[1][2]), rf * (plantpoly[2][1] - plantpoly[1][1])),
            {x = plantpoly[1][1], y = plantpoly[1][2], z = h}
        )
    }

    for i = 1, #plantpoly - 1 do
        local a = plantpoly[i]
        local b = plantpoly[i + 1]
        local r = math.atan2(rf * (b[2] - a[2]), rf * (b[1] - a[1]))
        local v = vec3.sub(b, a)
        local vn = vec3.normalize(v)

        local segmentLength = vec3.length(v)
        local segmentCount = math.floor(segmentLength / length + 0.5)
        if segmentCount == 0 then
            segmentCount = 1
        end

        local vs = vec3.mul(1 / segmentCount, v)

        for j = 1, segmentCount do
            local sa = vec3.add(a, vec3.mul(j - 1, vs))
            local sb = vec3.add(sa, vs)

            farmer.fenceSegment(sa, sb, center, fence, r, result)
        end
    end
end

function farmer.plan(result, type)
    if (farmer.finisherStore) then
        for i = 1, #farmer.finisherStore do
            local finisher = farmer.finisherStore[i]
            game.interface.bulldoze(finisher.id)
        end
    end

    farmer.finisherStore = {}

    for i = 1, #farmer.markerStore + 1 do
        result.models[#result.models + 1] = {
            id = "asset/snowball_farmer_marker.mdl",
            transf = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
        }
    end

    local poly = farmer.getPolygon(farmer.markerStore)
    local color = {1, 1, 0, 1}

    if poly then
        if #poly == 1 then
            local plantzone = {
                polygon = {{poly[1][1] - 5, poly[1][2], poly[1][3]}, {poly[1][1] + 5, poly[1][2], poly[1][3]}},
                draw = true,
                drawColor = color
            }
            game.interface.setZone("plantzone", plantzone)
        else
            local plantzone = {polygon = poly, draw = true, drawColor = color}
            game.interface.setZone("plantzone", plantzone)
        end
    end
end

function farmer.reset(result)
    result.models[#result.models + 1] = {
        id = "asset/snowball_farmer_finisher.mdl",
        transf = {0.01, 0, 0, 0, 0, 0.01, 0, 0, 0, 0, 0.01, 0, 0, 0, 0, 1}
    }

    game.interface.setZone("plantzone", nil)

    if not farmer.markerStore then
        return
    end

    for i = 1, #farmer.markerStore do
        local marker = farmer.markerStore[i]
        game.interface.bulldoze(marker.id)
    end

    farmer.markerStore = {}
end

function farmer.plant(result, ground, decoration, density, distribution, fence, interactive)
    result.models[#result.models + 1] = {
        id = "asset/snowball_farmer_finisher.mdl",
        transf = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1}
    }

    if not farmer.markerStore then
        return
    end

    game.interface.setZone("plantzone", nil)
    local plantpoly = farmer.getPolygon(farmer.markerStore)

    for i = 1, #farmer.markerStore do
        local marker = farmer.markerStore[i]
        game.interface.bulldoze(marker.id)
    end

    farmer.markerStore = {}

    if (not plantpoly) or (#plantpoly < 3) then
        return result
    end

    if poly.isSelfIntersecting(plantpoly) then
        return result
    end

    if decoration > 0 then
        farmer.decorate(plantpoly, decoration, density, distribution)
    end

    local center = poly.makeCentered(plantpoly)

    if fence then
        game.interface.buildConstruction(
            "asset/snowball_farmer_fence.con",
            {
                outline = plantpoly,
                fence = fence,
                center = {center[1], center[2], center[3]}
            },
            {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, center[1], center[2], center[3], 1}
        )        
    end

    if ground >= 0 then
        local entity =
            game.interface.buildConstruction(
            "asset/snowball_farmer_field.con",
            {
                outline = plantpoly,
                ground = ground,
                center = {center[1], center[2], center[3]}
            },
            {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, center[1], center[2], center[3], 1}
        )
        if interactive then
            local player = game.interface.getPlayer()
            game.interface.setPlayer(entity, player)
        end
    end
end

function farmer.lock(interactive)
    local player = nil
    if interactive then
        player = game.interface.getPlayer()
    end

    local fields =
        game.interface.getEntities(
        {pos = {0, 0}, radius = 100000},
        {type = "CONSTRUCTION", fileName = "asset/snowball_farmer_field.con"}
    )
    for i = 1, #fields do
        game.interface.setPlayer(fields[i], player)
    end
end

return farmer
