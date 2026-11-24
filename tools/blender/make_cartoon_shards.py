"""Turn Tim's cartoon target into the game's target file: its 4 parts plus
pre-broken shards for each part, so the game can break one part at a time.

Run with Blender (no window needed):
    blender --background --python tools/blender/make_cartoon_shards.py -- \\
        assets/targets/cartoon_target.glb assets/targets/cartoon_target_shards.glb
or, with Blender installed as the Python package `bpy`:
    python tools/blender/make_cartoon_shards.py assets/targets/cartoon_target.glb assets/targets/cartoon_target_shards.glb

Input: the model exported from assets/source/targets.blend, with convex parts
named Head, Left, Center and Right, a "Face" material (the artwork) and an
"Inside" material (broken edges).

Output, used by RangeTarget and Breakable:
  Part_Head, Part_Left, Part_Center, Part_Right   - the parts, as drawn intact
  Shards_Head, Shards_Left, ...                   - empties whose children are
                                                    that part's broken pieces
The artwork is reduced to 1024 x 1024 for phones. Every vertex's UV is its
position on the face in meters + 0.5 (as in the source model).
"""

import os
import sys

import bpy  # must come first when Blender runs as a Python package

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from impact_wall_tools import voronoi_fracture  # noqa: E402

PIECES = {"Head": 6, "Left": 5, "Center": 10, "Right": 5}
SEED = 23
TEXTURE_SIZE = 1024


def paths():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if len(args) < 2:
        sys.exit("usage: make_cartoon_shards.py <input.glb> <output.glb>")
    return os.path.abspath(args[0]), os.path.abspath(args[1])


def face_uvs(obj):
    """UV = position on the face in meters + 0.5, in world space."""
    mesh = obj.data
    uv = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        co = obj.matrix_world @ mesh.vertices[loop.vertex_index].co
        uv.data[loop.index].uv = (co.x + 0.5, co.z + 0.5)


def main():
    source, target = paths()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=source)

    # Make every part a top-level object with its transform applied.
    for obj in list(bpy.data.objects):
        if obj.type == 'MESH':
            world = obj.matrix_world.copy()
            obj.parent = None
            obj.matrix_world = world
    for obj in list(bpy.data.objects):
        if obj.type == 'EMPTY':
            bpy.data.objects.remove(obj, do_unlink=True)

    # Smaller artwork for phones.
    face = bpy.data.materials["Face"]
    for node in face.node_tree.nodes:
        if node.type == 'TEX_IMAGE' and node.image is not None:
            node.image.scale(TEXTURE_SIZE, TEXTURE_SIZE)
            node.image.pack()
    inside = bpy.data.materials["Inside"]

    total = 0
    for name, count in PIECES.items():
        part = bpy.data.objects[name]
        shards = voronoi_fracture(part, count, SEED + len(name), 0.4, inside)
        group = bpy.data.objects.new(f"Shards_{name}", None)
        bpy.context.scene.collection.objects.link(group)
        for i, shard in enumerate(shards):
            shard.name = f"{name}_{i:02d}"
            shard.data.name = shard.name
            face_uvs(shard)
            shard.parent = group
        part.name = f"Part_{name}"
        part.data.name = part.name
        total += len(shards)

    os.makedirs(os.path.dirname(target), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=target, export_format='GLB', export_yup=True,
                              export_apply=True, export_materials='EXPORT')
    print(f"Wrote {target}: {total} shards in {len(PIECES)} parts, artwork {TEXTURE_SIZE}px")


if __name__ == "__main__":
    main()
