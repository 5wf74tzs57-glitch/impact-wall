"""Build the Target Practice target and its pre-broken shards as one .glb file.

Run with Blender (no window needed):
    blender --background --python tools/blender/make_target_shards.py -- assets/targets/target_shards.glb
or, with Blender installed as the Python package `bpy`:
    python tools/blender/make_target_shards.py assets/targets/target_shards.glb

The file holds two things Godot uses:
  Intact  - the whole target board, shown until it's hit
  Shards  - an empty whose children are the broken pieces, in place

Every vertex gets a UV equal to its position on the board's face (0..1 across
the width and height), so one bullseye material looks right on the whole board
and on every shard. Faces made by the cuts use the "Inside" material.
"""

import os
import sys

import bpy  # must come first when Blender runs as a Python package
import bmesh

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from impact_wall_tools import voronoi_fracture  # noqa: E402

WIDTH = 0.6       # meters, left-right (Blender X)
HEIGHT = 0.6      # meters, up-down (Blender Z)
THICKNESS = 0.15  # meters, front-back (Blender Y); the front faces -Y, which becomes +Z in Godot
PIECES = 24
SEED = 7
CENTER_BIAS = 0.55


def output_path():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    return os.path.abspath(args[0] if args else "target_shards.glb")


def make_material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.8
    return mat


def face_uvs(obj, offset):
    """UV = where each vertex sits on the board's face, 0..1."""
    mesh = obj.data
    uv = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        co = mesh.vertices[loop.vertex_index].co + offset
        uv.data[loop.index].uv = (co.x / WIDTH + 0.5, co.z / HEIGHT + 0.5)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    face = make_material("Face", (0.95, 0.95, 0.92, 1.0))
    inside = make_material("Inside", (0.82, 0.74, 0.6, 1.0))  # raw board, like plywood

    mesh = bpy.data.meshes.new("Intact")
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= WIDTH
        v.co.y *= THICKNESS
        v.co.z *= HEIGHT
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(face)
    intact = bpy.data.objects.new("Intact", mesh)
    bpy.context.scene.collection.objects.link(intact)
    face_uvs(intact, intact.location)

    shards_root = bpy.data.objects.new("Shards", None)
    bpy.context.scene.collection.objects.link(shards_root)
    shards = voronoi_fracture(intact, PIECES, SEED, CENTER_BIAS, inside)
    for i, shard in enumerate(shards):
        shard.name = f"Shard_{i:02d}"
        shard.data.name = shard.name
        face_uvs(shard, shard.location)
        shard.parent = shards_root

    path = output_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True,
                              export_apply=True, export_materials='EXPORT')
    tris = sum(len(s.data.polygons) for s in shards)
    print(f"Wrote {path}: {len(shards)} shards, {tris} faces")


if __name__ == "__main__":
    main()
