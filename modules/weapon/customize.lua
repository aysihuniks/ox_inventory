if not lib then return end

local Items = require 'modules.items.client'

local customizeOpen = false
local previewObject = 0
local previewCam = 0
local activeSlot ---@type number?
local rotateHeading = 0.0
local previewBaseHeading = 205.0

local slotDefs = {
	{ id = 'flashlight', label = 'Flashlight', oxType = 'flashlight' },
	{ id = 'suppressor', label = 'Suppressor', oxType = 'muzzle', kind = 'suppressor' },
	{ id = 'muzzle', label = 'Muzzle', oxType = 'muzzle', kind = 'muzzle' },
	{ id = 'scope', label = 'Scope', oxType = 'sight' },
	{ id = 'barrel', label = 'Barrel', oxType = 'barrel' },
	{ id = 'magazine', label = 'Magazine', oxType = 'magazine' },
	{ id = 'grip', label = 'Grip', oxType = 'grip' },
	{ id = 'skin', label = 'Skin', oxType = 'skin' },
	{ id = 'tint', label = 'Tint', kind = 'tint' },
}

local function previewHeading()
	return GetEntityHeading(cache.ped) + previewBaseHeading + rotateHeading
end

local function matchesSlotKind(name, kind)
	if not kind then return true end

	local lower = name:lower()

	if kind == 'suppressor' then
		return lower:find('suppressor', 1, true) ~= nil
	elseif kind == 'muzzle' then
		return lower:find('suppressor', 1, true) == nil
	end

	return true
end

local function isTintConsumable(name)
	if not name:lower():find('tint', 1, true) then return false end

	local item = Items[name]
	return not item or not (item.weapon or item.component or item.ammo)
end

local function readWeaponHudStats(weaponHash)
	-- GetWeaponHudStats() just wouldn't give us a usable outData from Lua.
	-- Invoking 0xD92C739EE34C9EBA with our own blob works fine — no idea why the named wrapper doesn't.
	if not string.blob then return end

	local blob = string.blob(40)
	if not Citizen.InvokeNative(0xD92C739EE34C9EBA, weaponHash, blob) then return end

	local damage = blob:blob_unpack(1, '<I1')
	local speed = blob:blob_unpack(9, '<I1')
	local accuracy = blob:blob_unpack(25, '<I1')
	local range = blob:blob_unpack(33, '<I1')

	if damage == 0 and speed == 0 and accuracy == 0 and range == 0 then return end

	return damage, speed, accuracy, range
end

local function getCompatibleComponentHash(weaponHash, componentItem)
	local components = componentItem.client?.component
	if not components then return end

	for i = 1, #components do
		if DoesWeaponTakeWeaponComponent(weaponHash, components[i]) then
			return components[i]
		end
	end
end

local function weaponSupportsSlot(weaponHash, oxType, kind)
	if kind == 'tint' then return true end
	if not oxType then return false end

	for _, item in pairs(Items) do
		if type(item) == 'table' and item.component and item.type == oxType and matchesSlotKind(item.name, kind) then
			if getCompatibleComponentHash(weaponHash, item) then
				return true
			end
		end
	end
end

local function deletePreview()
	if previewCam ~= 0 then
		RenderScriptCams(false, true, 200, true, true)
		DestroyCam(previewCam, false)
		previewCam = 0
	end

	if previewObject ~= 0 and DoesEntityExist(previewObject) then
		DeleteObject(previewObject)
		previewObject = 0
	end

	ClearFocus()
end

local function ensureWeaponAsset(weaponHash)
	if HasWeaponAssetLoaded(weaponHash) then return true end

	RequestWeaponAsset(weaponHash, 31, 31)

	local timeout = GetGameTimer() + 5000
	while not HasWeaponAssetLoaded(weaponHash) and GetGameTimer() < timeout do
		Wait(0)
	end

	return HasWeaponAssetLoaded(weaponHash)
end

local function createPreviewObject(weaponHash, metadata, x, y, z)
	if previewObject ~= 0 and DoesEntityExist(previewObject) then
		DeleteObject(previewObject)
		previewObject = 0
	end

	previewObject = CreateWeaponObject(weaponHash, 0, x, y, z, true, 1.0, 0)

	if previewObject == 0 or not DoesEntityExist(previewObject) then
		previewObject = 0
		return false
	end

	SetEntityCollision(previewObject, false, false)
	FreezeEntityPosition(previewObject, true)
	SetEntityHeading(previewObject, previewHeading())
	SetEntityCoordsNoOffset(previewObject, x, y, z, false, false, false)

	if metadata.tint then
		SetWeaponObjectTintIndex(previewObject, metadata.tint)
	end

	local components = metadata.components
	if components then
		for i = 1, #components do
			local componentItem = Items[components[i]]
			if componentItem then
				local componentHash = getCompatibleComponentHash(weaponHash, componentItem)
				if componentHash then
					GiveWeaponComponentToWeaponObject(previewObject, componentHash)
				end
			end
		end
	end

	return true
end

local function spawnPreview(weaponHash, metadata)
	deletePreview()
	if not ensureWeaponAsset(weaponHash) then return end

	local coords = GetEntityCoords(cache.ped)
	local forward = GetEntityForwardVector(cache.ped)
	local x = coords.x + forward.x * 1.4
	local y = coords.y + forward.y * 1.4
	local z = coords.z + 0.35

	if not createPreviewObject(weaponHash, metadata, x, y, z) then return end

	previewCam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
	local camCoords = GetOffsetFromEntityInWorldCoords(previewObject, 0.2, 0.9, 0.14)
	SetCamCoord(previewCam, camCoords.x, camCoords.y, camCoords.z)
	PointCamAtEntity(previewCam, previewObject, 0.0, 0.0, 0.02, true)
	SetCamFov(previewCam, 38.0)
	SetCamActive(previewCam, true)
	RenderScriptCams(true, true, 200, true, true)
	SetFocusEntity(previewObject)
end

local function refreshPreview(weaponHash, metadata)
	if previewCam == 0 or previewObject == 0 or not DoesEntityExist(previewObject) then
		return spawnPreview(weaponHash, metadata)
	end

	if not ensureWeaponAsset(weaponHash) then return end

	local coords = GetEntityCoords(previewObject)
	if not createPreviewObject(weaponHash, metadata, coords.x, coords.y, coords.z) then
		return spawnPreview(weaponHash, metadata)
	end

	PointCamAtEntity(previewCam, previewObject, 0.0, 0.0, 0.0, true)
	SetFocusEntity(previewObject)
end

local function refreshActivePreview()
	local weapon = activeSlot and PlayerData.inventory[activeSlot]
	local data = weapon and Items[weapon.name]
	if data then
		refreshPreview(data.hash, weapon.metadata or {})
	end
end

local function buildState(slot)
	local item = PlayerData.inventory[slot]
	if not item then return end

	local data = Items[item.name]
	if not data?.weapon or data.throwable then return end

	local metadata = item.metadata or {}
	local components = metadata.components or {}
	local attachedByType = {}

	for i = 1, #components do
		local componentName = components[i]
		local componentItem = Items[componentName]
		if componentItem?.type then
			attachedByType[componentItem.type] = {
				name = componentName,
				label = componentItem.label,
			}
		end
	end

	local slots = {}

	for i = 1, #slotDefs do
		local def = slotDefs[i]
		if not weaponSupportsSlot(data.hash, def.oxType, def.kind) then goto skipSlot end

		local typeAttached = def.oxType and attachedByType[def.oxType]
		local attached = typeAttached

		if attached and def.kind and not matchesSlotKind(attached.name, def.kind) then
			attached = nil
		end

		local available = {}

		-- suppressor/muzzle share type; only list options on the matching pin
		if not typeAttached or attached then
			for invSlot, invItem in pairs(PlayerData.inventory) do
				local invData = invItem and Items[invItem.name]
				if invData then
					if def.kind == 'tint' then
						if isTintConsumable(invItem.name) then
							available[#available + 1] = {
								slot = invSlot,
								name = invItem.name,
								label = invItem.metadata?.label or invData.label,
								count = invItem.count,
								image = invData.client?.image,
								kind = 'tint',
							}
						end
					elseif invData.component and invData.type == def.oxType and matchesSlotKind(invItem.name, def.kind) then
						if getCompatibleComponentHash(data.hash, invData) then
							available[#available + 1] = {
								slot = invSlot,
								name = invItem.name,
								label = invItem.metadata?.label or invData.label,
								count = invItem.count,
								image = invData.client?.image,
								kind = 'component',
							}
						end
					end
				end
			end

			table.sort(available, function(a, b)
				return a.label < b.label
			end)
		end

		local equipped

		if def.kind == 'tint' then
			if metadata.weapontint then
				equipped = { name = 'tint', label = metadata.weapontint }
			end
		elseif attached then
			equipped = { name = attached.name, label = attached.label }
		end

		if def.kind ~= 'tint' or equipped or available[1] then
			slots[#slots + 1] = {
				id = def.id,
				label = def.label,
				oxType = def.oxType,
				attached = equipped,
				available = available,
			}
		end

		::skipSlot::
	end

	local ammoType
	if data.ammoname then
		local ammoItem = Items[data.ammoname]
		ammoType = ammoItem and ammoItem.label or data.ammoname
	end

	local damage, fireRate, accuracy, range = readWeaponHudStats(data.hash)

	return {
		slot = slot,
		name = item.name,
		label = metadata.label or data.label,
		serial = metadata.serial,
		durability = metadata.durability,
		ammo = metadata.ammo,
		ammoType = ammoType,
		damage = damage,
		fireRate = fireRate,
		accuracy = accuracy,
		range = range,
		tint = metadata.weapontint or metadata.tint,
		components = components,
		slots = slots,
	}
end

local function closeCustomize(reopenInventory)
	if not customizeOpen then return end

	customizeOpen = false
	activeSlot = nil
	rotateHeading = 0.0
	deletePreview()
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
	SendNUIMessage({ action = 'closeWeaponCustomize' })
	DisplayRadar(true)

	if reopenInventory then
		client.openInventory()
	end
end

local function pushState()
	if not customizeOpen or not activeSlot then return end

	local state = buildState(activeSlot)
	if state then
		SendNUIMessage({ action = 'openWeaponCustomize', data = state })
	else
		closeCustomize(true)
	end
end

local function openCustomize(slot)
	local item = PlayerData.inventory[slot]
	if not item then return end

	local data = Items[item.name]
	if not data?.weapon or data.throwable then return end

	TriggerEvent('ox_inventory:disarm', true)
	client.closeInventory()

	activeSlot = slot
	rotateHeading = 0.0
	customizeOpen = true
	DisplayRadar(false)

	spawnPreview(data.hash, item.metadata or {})

	local state = buildState(slot)
	if not state then
		closeCustomize(true)
		return
	end

	SetNuiFocus(true, true)
	SetNuiFocusKeepInput(false)
	SendNUIMessage({ action = 'openWeaponCustomize', data = state })
end

local function applyComponent(weaponSlot, componentInvSlot)
	local weapon = PlayerData.inventory[weaponSlot]
	local component = PlayerData.inventory[componentInvSlot]
	if not weapon or not component then return false end

	local weaponData = Items[weapon.name]
	local componentData = Items[component.name]
	if not weaponData?.weapon or not componentData?.component then return false end

	local componentHash = getCompatibleComponentHash(weaponData.hash, componentData)
	if not componentHash then
		lib.notify({ id = 'component_invalid', type = 'error', description = locale('component_invalid', componentData.label) })
		return false
	end

	local weaponComponents = weapon.metadata.components or {}
	for i = 1, #weaponComponents do
		if componentData.type == Items[weaponComponents[i]]?.type then
			lib.notify({ id = 'component_slot_occupied', type = 'error', description = locale('component_slot_occupied', componentData.type) })
			return false
		end
	end

	local success = lib.callback.await('ox_inventory:updateWeapon', false, 'component', tostring(componentInvSlot), weaponSlot)
	if not success then return false end

	local refreshed = PlayerData.inventory[weaponSlot]
	refreshPreview(weaponData.hash, refreshed?.metadata or {})
	return true
end

local function removeAttachedComponent(weaponSlot, componentName)
	local success = lib.callback.await('ox_inventory:updateWeapon', false, 'component', {
		slot = weaponSlot,
		component = componentName,
	})

	if not success then return false end

	local weapon = PlayerData.inventory[weaponSlot]
	local weaponData = weapon and Items[weapon.name]
	if weaponData then
		refreshPreview(weaponData.hash, weapon.metadata or {})
	end

	return true
end

RegisterNUICallback('openWeaponCustomize', function(data, cb)
	cb(1)
	local slot = data?.slot
	if type(slot) ~= 'number' then return end
	openCustomize(slot)
end)

RegisterNUICallback('weaponCustomizeClose', function(_, cb)
	cb(1)
	closeCustomize(true)
end)

RegisterNUICallback('weaponCustomizeApply', function(data, cb)
	cb(1)
	if not customizeOpen or not activeSlot then return end

	local componentSlot = data?.slot
	if type(componentSlot) ~= 'number' then return end

	local invItem = PlayerData.inventory[componentSlot]
	if not invItem then return end

	if isTintConsumable(invItem.name) then
		if lib.callback.await('ox_inventory:customizeApplyTint', false, activeSlot, componentSlot) then
			refreshActivePreview()
			pushState()
		end
		return
	end

	if applyComponent(activeSlot, componentSlot) then
		Wait(50)
		pushState()
	end
end)

RegisterNUICallback('weaponCustomizeRemove', function(data, cb)
	cb(1)
	if not customizeOpen or not activeSlot then return end

	local componentName = data?.component
	if type(componentName) ~= 'string' or componentName == '' then return end

	if componentName == 'tint' then
		if lib.callback.await('ox_inventory:customizeClearTint', false, activeSlot) then
			refreshActivePreview()
			pushState()
		end
		return
	end

	removeAttachedComponent(activeSlot, componentName)
	pushState()
end)

RegisterNUICallback('weaponCustomizeRotate', function(data, cb)
	cb(1)
	if not customizeOpen or previewObject == 0 or not DoesEntityExist(previewObject) then return end

	local delta = tonumber(data?.delta) or 0
	rotateHeading = rotateHeading + delta
	SetEntityHeading(previewObject, previewHeading())
end)

AddEventHandler('onResourceStop', function(resource)
	if resource == shared.resource then
		closeCustomize()
	end
end)

return {
	open = openCustomize,
	close = closeCustomize,
	isOpen = function()
		return customizeOpen
	end,
}
