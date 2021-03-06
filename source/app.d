import std.algorithm;
import std.array;
import std.file;
import std.format;
import std.regex;
import std.stdio;
import std.string;

immutable string STUB_MODEL = import("stubModel.json");
immutable string STUB_OVERRIDE = import("stubOverride.json");
immutable string STUB_PREDICATE = import("stubPredicate.json");

static string[string] forwards;

string namespace = "example";

Override[][Identifier] knownOverrides; 

void main(string[] args) {
	forwards["matchItems"] = "items";
	forwards["matchItem"] = "items"; // Is this even valid cit?
	forwards["tile"] = "texture";

	string filename = "in";
	string citDir = filename ~ "/assets/minecraft/optifine/cit";
	if (citDir.exists && citDir.isDir) {
		citDir.dirEntries(SpanMode.depth)
			.each!((string file) {
				if (file.endsWith(".properties")) {
					attemptConversion(file);
				}
			});
	}
	foreach (Identifier item, Override[] o; knownOverrides) {
		generateOverride(item, o);
	}
}

void attemptConversion(string file) {
	file = file.replace('\\', '/');
	string[] lines = (cast(string) read(file)).split("\n");

	Identifier[] items;
	Range[] counts;
	Type type = Type.ITEM;
	string texture;
	string model;

	foreach (string line; lines) {
		string[] parts = line.split("=");
		if (parts.length > 1) {
			string name = parts[0].strip();
			string value = parts[1..$].join("=").strip();
			if (name in forwards) {
				name = forwards[name];
			}
			if (name == "type") {
				try {
					type = cast(Type) value;
				} catch (Exception e) {
					writefln("File %s used invalid type %s", file, value);
					return;
				}
			} else if (name == "stackSize") {
				counts = value.split(' ').map!(v => Range(v)).array;
			} else if (name == "items") {
				items = value.split(' ').map!(v => Identifier(v)).array;
			} else if (name == "texture") {
				texture = value;
			} else if (name == "model") {
				model = value;
			} else {
				writefln("Unrecognized property %s in %s", name, file);
				return;
			}
		}
	}
	if (type == Type.ITEM) {
		if (items.length == 0) {
			writefln("Missing list of items for %s", file);
			return;
		}
		if (model.length != 0) {
		} else {
			if (texture.length == 0) {
				texture = file.split('/')[$ - 1][0..$ - 11];
			}
			if (texture.canFind('/')) {
				texture = "assets/minecraft/" ~ texture;
			} else {
				texture = file.split('/')[0..$ - 1].join('/') ~ '/' ~ texture;
			}
			if (!texture.endsWith(".png")) {
				texture ~= ".png";
			}
			generateStubModel(texture);
			model = "%s:item/%s".format(namespace, sanitizeItemName(texture.split('/')[$ - 1][0..$ - 4]));
		}
		foreach (Identifier item; items) {
			string[] predicates;
			if (counts.length > 0) {
				predicates ~= `"count": "%s"`.format(counts[0].chimeRange);
			}
			if (!(item in knownOverrides)) {
				knownOverrides[item] = [Override(predicates, model)];
			} else {
				knownOverrides[item] ~= Override(predicates, model);
			}
		}
	} else if (type == Type.ENCHANTMENT) {
		writefln("Chime currently does not support enchantment overrides, skipping %s", file);
	} else if (type == Type.ARMOR) {
		writeln("armor");
	} else if (type == Type.ELYTRA) {
		writefln("Chime currently does not support elytra overrides, skipping %s", file);
	}
}

string sanitizeItemName(string name) {
	return name.replaceAll(ctRegex!"[^a-z0-9\\/._-]", "_");
}

void generateStubModel(string texture) {
	string itemName = sanitizeItemName(texture.split('/')[$ - 1][0..$ - 4]);
	string path = "out/assets/%s/models/item".format(namespace);
	path.mkdirRecurse;
	path ~= "/%s.json".format(itemName);
	std.file.write(path, STUB_MODEL.format(namespace, itemName));
	path = "out/assets/%s/textures/item".format(namespace);
	path.mkdirRecurse;
	path ~= "/%s.png".format(itemName);
	copy(texture, path);
	if (exists(texture ~ ".mcmeta")) {
		copy (texture ~ ".mcmeta", path ~ ".mcmeta");
	}
}

void generateOverride(Identifier item, Override[] overrides) {
	string path = "out/assets/%s/overrides/item".format(item.namespace);
	path.mkdirRecurse();
	path ~= "/%s.json".format(item.path);
	std.file.write(path, STUB_OVERRIDE
		.format(overrides
			.map!(o => STUB_PREDICATE
				.format(o.predicates.join(",\n"), o.model))
			.array.join(",\n")));
}

struct Override {
	string[] predicates;
	string model;
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

enum Type {
	ITEM = "item",
	ENCHANTMENT = "enchantment",
	ARMOR = "armor",
	ELYTRA = "elytra"
}