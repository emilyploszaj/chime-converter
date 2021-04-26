import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.format;
import std.regex;
import std.stdio;
import std.string;

immutable string STUB_MODEL = import("stubModel.json");
immutable string STUB_OVERRIDE = import("stubOverride.json");
immutable string STUB_PREDICATE = import("stubPredicate.json");

static string[string] forwards;

string namespace = "converted";
string citDir;

Override[][Identifier] knownOverrides;

immutable filename = "in";
immutable outFilename = "out";

void main(string[] args) {
	forwards = [
		"matchItems": "items",
		"matchItem": "items", // Is this even valid cit?
		"tile": "texture",
		"texture.bow_standby": "texture"
	];

	// Allow for dir to be called 'optifine' or 'mcpatcher'
	citDir = filename ~ "/assets/minecraft/optifine/cit";
	if (!citDir.exists) {
		citDir = filename ~ "/assets/minecraft/mcpatcher/cit";
	}
	if (citDir.exists && citDir.isDir) {
		writefln("Found optifine/mcpatcher folder at: %s", citDir);
		writeln("\n--Converting Files--");
		citDir.dirEntries(SpanMode.depth).each!((string file) {
			if (file.endsWith(".properties")) {
				try {
					attemptConversion(file);
				} catch (Exception e) {
					writeln(e.msg);
				}
			}
		});
	} else {
		writeln("Could not find optifine/mcpatcher folder");
		return;
	}
	writeln("\n--Generating Overrides--");
	foreach (Identifier item, Override[] o; knownOverrides) {
		generateOverride(item, o);
	}
	copy(filename ~ "/pack.mcmeta", "out/pack.mcmeta");
	copy(filename ~ "/pack.png", "out/pack.png");
}

void attemptConversion(string file) {
	file = file.replace('\\', '/');
	string[] lines = (cast(string) read(file)).split("\n");

	Identifier[] items;
	Range[] counts;
	Range[] damages;
	Nbt[] nbts;
	Type type = Type.ITEM;
	string texture;
	ExtraTexture[] textures;
	string model;
	int weight = 0;

	writefln("Converting file %s", file);
	foreach (string line; lines) {
		string[] parts = line.split("=");
		if (parts.length > 1) {
			string name = parts[0].strip();
			string value = parts[1..$].join("=").strip();
			string[] splitname = name.split(".");

			// Check for aliases
			if (name in forwards) {
				name = forwards[name];
			} else if (matchFirst(splitname[1], 
				"[leather|golde?n?|iron|diamond|netherite]_[boots|leggings|chestplate|helmet]_overlay")) {
				name = "texture";
			}
			switch(name) {
				case "type":
					try {
						type = cast(Type) value;
					} catch (Exception e) {
						throw new Exception("File %s used invalid type %s".format(file, value));	
					}
					break;
				case "stackSize":
					counts = value.split(' ').map!(v => Range(v)).array;
					break;
				case "items":
					items = value.split(' ').map!(v => Identifier(v)).array;
					break;
				case "texture":
					texture = value;
					break;	
				case "damage":	
					damages = value.split(' ').map!(v => Range(v)).array;	
					break;
				case "model":
					model = value;
					break;
				case "weight":
					weight = parse!int(value);
					break;
				case "useGlint":
					writefln("Chime does not support property %s", name);
					break;
				default:
					if (splitname[0] == "texture") {
						textures ~= ExtraTexture(splitname[1], value);
					} else if (splitname[0] == "nbt") {
						nbts ~= Nbt(splitname,value);
					} else {
						throw new Exception("Unrecognized property %s".format(name));
					}
			}
		}
	}
	ConversionFile cFile = ConversionFile(file, items, counts, damages, nbts, type, texture, textures, model, weight);
	generatePredicate(cFile);
}

void generatePredicate(ConversionFile cFile) {
	string subPath = sanitize(cFile.fileName.split("/")[citDir.split("/").length..$-1].join("/"));
	if (subPath != "") { subPath ~= "/"; }
	switch(cFile.type){
		case Type.ITEM:

			if (cFile.items.length == 0) {
				writefln("Missing list of items for %s", cFile.fileName);
				return;
			}
			
			if (cFile.model.length == 0) {
				//generate a model
				cFile.model = generateModel(cFile.items, cFile.texture, cFile.fileName.split('/'), subPath);
			} else {
				//custom model
				try {
					cFile.model = editModel(cFile.model, cFile.texture, cFile.fileName.split('/'), subPath);
				} catch (Exception e) {
					writeln(e);
				}
			}

			foreach (Identifier item; cFile.items) {
				if (item.path == "skull") {
					item.path = "player_head";
					cFile.damages = [];
				}
				string[] predicates;
				if (cFile.counts.length > 0) {
					predicates ~= `"count": "%s"`.format(cFile.counts[0].chimeRange);
				}
				if (cFile.damages.length > 0) {
					predicates ~= `"damage": %s`.format(cFile.damages[0].chimeRange);
				}
				if (cFile.nbts.length > 0) {
					predicates ~= cFile.nbts.map!(generatePredicateNbt).array;
				}
				if (!(item in knownOverrides)) {
					knownOverrides[item] = [Override(predicates, cFile.model, cFile.weight, Type.ITEM)];
				} else {
					knownOverrides[item] ~= Override(predicates, cFile.model, cFile.weight, Type.ITEM);
				}

				foreach (ExtraTexture et; cFile.textures) {
					string[string] predicateAliases = [
						"fishing_rod_cast": "\"cast\": 1",
						"bow_pulling_0": `"pulling": 1`,
						"bow_pulling_1": "\"pulling\": 1,\n\t\t\t\t\"pull\": 0.65",
						"bow_pulling_2": "\"pulling\": 1,\n\t\t\t\t\"pull\": 0.9",
					];
					if (et.texture in predicateAliases) {
						et.texture = "\t\t\t\t" ~ predicateAliases[et.texture];
					} else {
						throw new Exception("Unknown extra texture %s".format(et.texture));
					}
					et.value = et.value.chompPrefix("./").chomp(".png");
					string modelPath = "%s:item/%s".format(namespace, subPath ~ et.value);
					generateModel(cFile.items, et.value, cFile.fileName.split('/'), subPath);
					string[] extraPredicates = predicates;
					extraPredicates ~=  et.texture;

					knownOverrides[item] ~= Override(extraPredicates, modelPath, cFile.weight, Type.ITEM);
				}
				
			}
			break;
		case "block":	
		case Type.ARMOR:
			writefln("Chime converter does not yet support armor overrides, skipping %s", cFile.fileName);
			break;
		case Type.ENCHANTMENT:
			writefln("Chime currently does not support enchantment overrides, skipping %s", cFile.fileName);
			break;
		case Type.ELYTRA:
			writefln("Chime currently does not support elytra overrides, skipping %s", cFile.fileName);
			break;
		default:
			writefln("Unknown type %s", cFile.type);
			break;
	}
}

string sanitize(string name) {
	return name.replaceAll(ctRegex!"[^a-z0-9\\/._-]", "_");
}

string generateModel(Identifier[] vanillaItems, string texture, string[] path, string subPath) {
	if (texture.length == 0) {
		texture = path[$ - 1][0..$ - 11];
	}
	texture = chompPrefix(texture, "./");
	if (!texture.endsWith(".png")) {
		texture ~= ".png";
	}
	try {
		copyTexture("assets/minecraft/" ~ texture, subPath);
	} catch(FileException e) {
		texture = path[0..$ - 1].join('/') ~ '/' ~ texture;
		copyTexture(texture, subPath);
	}
	
	string parent = "generated";
	foreach (Identifier vanillaItem; vanillaItems) {
		if (matchFirst(vanillaItem.path, ".*(_pickaxe|_axe|_sword|_shovel|_hoe|bow)")) {	
			parent = "handheld";
			break;
		} else if (vanillaItem.path == "fishing_rod") {
			parent = "handheld_rod";
		}
	}
	string itemName = sanitize(texture.split('/')[$ - 1].chomp(".png"));
	string file = generatePath(namespace, "models", "item", subPath) ~ "%s.%s".format(itemName, "json");	

	std.file.write(file, STUB_MODEL
		.format(parent, namespace, subPath~itemName));

	return "%s:item/%s".format(namespace, subPath ~ itemName);
}

string editModel(string model, string texture, string[] path, string subPath) {

	model = chompPrefix(model, "./");
	if (!model.endsWith(".json")) {
		model ~= ".json";
	}
	string modelFromPath = (path[0..$ - 1] ~ model).join('/');
	string modelToPath = generatePath(namespace, "models", "item", subPath)~"%s".format(model);
	model = "%s:item/%s%s".format(namespace, subPath, sanitize(model.split('/')[$ - 1][0..$ - 5]));
	string modelFile = cast(string) read(modelFromPath);
	int[] texturePos;
	try {
		texturePos = findValue(modelFile, `"layer0"`);
	} catch (Exception e) {
		//Custom model without texture
		std.file.write(modelToPath, modelFile);
		return model;
	}

	if (!texture) {
		texture = modelFile[texturePos[0]..texturePos[1]].chompPrefix("./").chomp(".png");
		if (texture.canFind('/')) {
			texture = "%s/assets/minecraft/%s.png".format(filename,texture);
		} else {
			texture = modelFromPath[0..modelFromPath.lastIndexOf("/")+1]~"%s.png".format(texture);
		}
	} else {
		texture = texture.chompPrefix("./").chomp(".png")~".png";
		if (texture.canFind('/')) {
			texture = "%s/assets/minecraft/%s".format(filename,texture);
		} else {
			texture = (path[0..$ - 1] ~ texture).join('/');
		}
	}
	copyTexture(texture, subPath);
	texture = texture.split("/")[$ - 1].chomp(".png");
	string editedModel = modelFile[0..texturePos[0]] ~
		"%s:item/%s".format(namespace, subPath ~ texture) ~
		modelFile[texturePos[1]..$];
	std.file.write(modelToPath,editedModel);
	
	return model;
}

int[] findValue(string file, string prop) {
	int pos1 = to!int(indexOf(file, prop));
	if (pos1 == -1) {
		throw new Exception("Cannot find property %s in file %s".format(prop, file));
	} else {
		pos1 = to!int(indexOf(file, `"`, pos1 + prop.length) + 1);

		return [pos1, to!int(indexOf(file, `"`, pos1 + 1))];
	}
}

void copyTexture(string texture, string subPath) {
	string itemName = sanitize(texture.split('/')[$ - 1].chomp(".png"));
	string path = generatePath(namespace, "textures", "item", subPath) ~ "%s.png".format(itemName);
	if (itemName == "null") {
		writefln("Skipping copying "~texture);
		return;
	}
	copy(texture, path);
	if (exists(texture ~ ".mcmeta")) {
		copy(texture ~ ".mcmeta", path ~ ".mcmeta");
	}
}

void generateOverride(Identifier item, Override[] overrides) {
	writefln("Generating Override %s:%s", item.namespace, item.path);
	sort!((a,b)=>a.weight < b.weight)(overrides);
	std.file.write(generatePath(item.namespace, "overrides", "item")~"%s.json".format(item.path), STUB_OVERRIDE
		.format(overrides
			.map!(o => STUB_PREDICATE
				.format(o.predicates.join(",\n"), "model", o.model))
			.array.join(",\n")));
}

string generatePredicateNbt(Nbt nbt) {
	string nbtData = nbt.nbttag.split(':')[1..$].join(":");			
	if (matchFirst(nbt.nbttag,"i?pattern|i?regex")) {
		if (matchFirst(nbt.nbttag,"i?pattern")) {
		nbtData = nbtData.replace("*",".*");
		}

		if (startsWith(nbt.nbttag,"i")) {
			nbtData = "(?i)" ~ nbtData;
		}
		nbt.nbttag = "/%s/".format(nbtData);
	}

	string p = "%s";
	foreach(string nbtelement; nbt.nbtpath) {
		p = p.format(`"%s": `.format(nbtelement)~"{%s}");
	}
	return p.replace("{%s}",`"%s"`.format(nbt.nbttag));
}

string generatePath(string nspace, string pathType, string type, string subPath = null) {
	string path = "%s/assets/%s/%s/%s/".format(outFilename, nspace, pathType, type);
	if (subPath) {
		path ~= subPath;
	}
	path.mkdirRecurse();
	return path;
}

struct Override {
	string[] predicates;
	string model;
	int weight;
	Type type;
}

struct Nbt {
	string[] nbtpath;
	string nbttag;
}

struct ExtraTexture {
	string texture;
	string value;
}

struct Range {
	string chimeRange;

	this(string range) {
		string[] parts = range.split('-');
		if (parts.length == 1) {
			chimeRange = range;
		} else {
			if (parts[0].length == 0) {
				chimeRange = "<=%s".format(parts[1]);
			} else if (parts[1].length == 0) {
				chimeRange = ">=%s".format(parts[0]);
			} else {
				chimeRange = "[%s..%s]".format(parts[0], parts[1]);
			}
		}
	}
}

struct Identifier {
	string namespace, path;

	this(string s) {
		string[] parts = s.split(":");
		if (parts.length > 1) {
			namespace = parts[0];
			path = parts[1];
		} else {
			namespace = "minecraft";
			path = s;
		}
	}
}

struct ConversionFile {
	string fileName;
	Identifier[] items;
	Range[] counts;
	Range[] damages;
	Nbt[] nbts;
	Type type = Type.ITEM;
	string texture;
	ExtraTexture[] textures;
	string model;
	int weight;
}

enum Type : string {
	ITEM = "item",
	ENCHANTMENT = "enchantment",
	ARMOR = "armor",
	ELYTRA = "elytra"
}
