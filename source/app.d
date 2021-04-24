import std.algorithm;
import std.array;
import std.conv;
import std.file;
import std.format;
import std.regex;
import std.stdio;
import std.string;

immutable string STUB_MODEL = import("stubModel.json");
immutable string STUB_MODEL_HANDHELD = import("stubModelHandheld.json");
immutable string STUB_OVERRIDE = import("stubOverride.json");
immutable string STUB_PREDICATE = import("stubPredicate.json");

static string[string] forwards;

string namespace = "converted";
string citDir;

Override[][Identifier] knownOverrides;

immutable filename = "in";
immutable outFilename = "out";

void main(string[] args) {
	forwards["matchItems"] = "items";
	forwards["matchItem"] = "items"; // Is this even valid cit?
	forwards["tile"] = "texture";

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
				attemptConversion(file);
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
			}
			switch(name) {
				case "type":
					try {
						type = cast(Type) value;
					} catch (Exception e) {
						writefln("File %s used invalid type %s", file, value);
						return;
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
						//writefln("special texture %s",splitname);
						return;
					} else if (splitname[0] == "nbt") {
						nbts ~= Nbt(splitname,value);
					} else {
						writefln("Unrecognized property %s", name);
						return;
					}
			}
		}
	}
	string subPath = sanitize(file.split("/")[citDir.split("/").length..$-1].join("/"));
	switch(type){
		case Type.ITEM:

			if (items.length == 0) {
				writefln("Missing list of items for %s", file);
				return;
			}
			
			if (model.length == 0) {
				//generate a model
				model = generateModel(items, texture, file.split('/'), subPath);
			} else {
				//custom model
				try {
					model = editModel(model, texture, file.split('/'), subPath);
				} catch (Exception e) {
					writeln(e);
				}
			}

			foreach (Identifier item; items) {
				if (item.path == "skull") {
					item.path = "player_head";
					damages = [];
				}
				string[] predicates;
				if (counts.length > 0) {
					predicates ~= `"count": "%s"`.format(counts[0].chimeRange);
				}
				if (damages.length > 0) {
					predicates ~= `"damage": %s`.format(damages[0].chimeRange);
				}
				if (nbts.length > 0) {
					predicates ~= nbts.map!(generatePredicateNbt).array;
				}
				if (!(item in knownOverrides)) {
					knownOverrides[item] = [Override(predicates, model, weight, Type.ITEM)];
				} else {
					knownOverrides[item] ~= Override(predicates, model, weight, Type.ITEM);
				}
			}
			break;
		case "block":	
		case Type.ARMOR:
			writefln("Chime converter does not yet support armor overrides, skipping %s", file);
			break;
		case Type.ENCHANTMENT:
			writefln("Chime currently does not support enchantment overrides, skipping %s", file);
			break;
		case Type.ELYTRA:
			writefln("Chime currently does not support elytra overrides, skipping %s", file);
			break;
		default:
			throw new Exception("Cannot type %s".format(type));
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
	string itemName = sanitize(texture.split('/')[$ - 1].chomp(".png"));
	string stub = STUB_MODEL;
	foreach (Identifier vanillaItem; vanillaItems) {
		if (matchFirst(vanillaItem.path, ".*(_pickaxe|_axe|_sword|_shovel|_hoe)")) {	
			stub = STUB_MODEL_HANDHELD;
		}
	}
	string file = generatePath(namespace, "models", "item", subPath) ~ "/%s.%s".format(itemName, "json");

	std.file.write(file, stub
		.format(namespace, subPath~"/"~itemName));

	return "%s:item/%s/%s".format(namespace, subPath, itemName);
}

string editModel(string model, string texture, string[] path, string subPath) {


	model = chompPrefix(model, "./");
	if (!model.endsWith(".json")) {
		model ~= ".json";
	}
	string modelFromPath = (path[0..$ - 1] ~ model).join('/');
	string modelToPath = generatePath(namespace, "models", "item", subPath)~"/%s".format(model);
	string modelFile = cast(string) read(modelFromPath);
	auto texturePos = indexOf(modelFile, `"layer0"`, 0);
	if (texturePos == -1) {
		throw new Exception("Chime Converter does not support custom models without a texture");
	}
	texturePos = indexOf(modelFile, `"`, texturePos + 8) + 1;
	auto textureEndPos = indexOf(modelFile, `"`, texturePos + 1);
		
	if (!texture) {
			texture = modelFile[texturePos..textureEndPos].chompPrefix("./").chomp(".png");
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
		string editedModel = modelFile[0..texturePos] ~
			"%s:item/%s".format(namespace, subPath ~ "/" ~ texture) ~
			modelFile[textureEndPos..$];
		std.file.write(modelToPath,editedModel);

	return "%s:item/%s/%s".format(namespace, subPath, sanitize(model.split('/')[$ - 1][0..$ - 5]));
}


void copyTexture(string texture, string subPath) {
	string itemName = sanitize(texture.split('/')[$ - 1].chomp(".png"));
	string path = generatePath(namespace, "textures", "item", subPath) ~ "/%s.png".format(itemName);
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
	std.file.write(generatePath(item.namespace, "overrides", "item")~"/%s.json".format(item.path), STUB_OVERRIDE
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
			nbtData = "(?i)%s".format(nbtData);
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
	string path = "%s/assets/%s/%s/%s".format(outFilename, nspace, pathType, type);
	if (subPath) {
		path ~= "/" ~ subPath;
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

enum Type : string {
	ITEM = "item",
	ENCHANTMENT = "enchantment",
	ARMOR = "armor",
	ELYTRA = "elytra"
}
