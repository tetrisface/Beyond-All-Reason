return {
	raptor_turret_meteor_t4_v1 = {
		maxacc = 0.0115,
		activatewhenbuilt = true,
		autoheal = 1,
		maxdec = 0.0115,
		energycost = 6000,
		metalcost = 240,
		builddistance = 500,
		builder = false,
		buildpic = "raptors/raptor_turretxl_meteor.DDS",
		buildtime = 5200,
		canattack = true,
		canreclaim = false,
		canrestore = false,
		canstop = "1",
		capturable = false,
		category = "RAPTOR",
		collisionvolumeoffsets = "0 -15 0",
		collisionvolumescales = "80 50 80",
		collisionvolumetype = "box",
		explodeas = "tentacle_death",
		footprintx = 8,
		footprintz = 8,
		hightrajectory = 1,
		idleautoheal = 15,
		idletime = 300,
		levelground = false,
		mass = 1400,
		health = 30000,
		maxslope = 255,
		speed = 0.0,
		maxwaterdepth = 0,
		movementclass = "NANO",
		noautofire = false,
		nochasecategory = "MOBILE",
		objectname = "Raptors/raptor_turretxl_meteor_v2.s3o",
		repairable = true,
		script = "Raptors/raptor_turretxl_v2.cob",
		seismicsignature = 0,
		selfdestructas = "tentacle_death",
		side = "THUNDERBIRDS",
		sightdistance = 500,
		smoothanim = true,
		turninplace = true,
		turninplaceanglelimit = 90,
		turnrate = 1840,
		unitname = "raptord2",
		upright = false,
		waterline = 1,
		workertime = 100,
		yardmap = "oooooooo oooooooo oooooooo oooooooo oooooooo oooooooo oooooooo oooooooo",
		customparams = {
			subfolder = "other/raptors",
			model_author = "LathanStanley, Beherith",
			normalmaps = "yes",
			normaltex = "unittextures/chicken_l_normals.png",
			treeshader = "yes",
		},
		sfxtypes = {
			explosiongenerators = {
				[1] = "custom:blood_spray",
				[2] = "custom:blood_explode",
				[3] = "custom:dirt",
			},
			pieceexplosiongenerators = {
				[1] = "blood_spray",
				[2] = "blood_spray",
				[3] = "blood_spray",
			},
		},
		weapondefs = {
			weapon = {
				areaofeffect = 1920,
				avoidfriendly = 0,
				cegtag = "nuketrail-roost",
				collidefriendly = 0,
				commandfire = true,
				craterareaofeffect = 1920,
				craterboost = 2.4,
				cratermult = 1.2,
				edgeeffectiveness = 0.5,
				explosiongenerator = "custom:newnukecor",
				firestarter = 70,
				hightrajectory = 1,
				interceptedbyshieldtype = 0,
				model = "Raptors/greyrock2.s3o",
				name = "METEORLAUNCHER",
				proximitypriority = -1,
				range = 72000,
				reloadtime = 30,
				soundhit = "nukecor",
				soundhitwet = "nukewater",
				soundstart = "bugarty",
				targetable = 1,
				targetborder = 0.75,
				turret = 1,
				weaponvelocity = 1500,
				damage = {
					default = 30000,
				},
				customparams = {
					shield_aoe_penetration = true,
				}
			},
		},
		weapons = {
			[1] = {
				def = "WEAPON",
				onlytargetcategory = "NONE",
			},
		},
	},
}
