"""Build the person-shaped range target and its pre-broken shards as one .glb.

Run with Blender (no window needed):
    blender --background --python tools/blender/make_person_target.py -- assets/targets/person_target.glb
or, with Blender installed as the Python package `bpy`:
    python tools/blender/make_person_target.py assets/targets/person_target.glb

The shape is a head-and-shoulders silhouette: a round head on a torso with
sloped shoulders, 0.6 m wide and about 0.92 m tall, 0.12 m thick. The fracture
tool only handles convex shapes, so the head and the torso are broken
separately and their shards are put together.

The file holds (like make_target_shards.py):
  Intact  - the whole silhouette, shown until it's hit
  Shards  - an empty whose children are the broken pieces, in place
Every vertex's UV is its position on the face in meters + 0.5 (so the shader
can draw the outline and bullseye in real units). Cut faces use "Inside".
Keep these numbers in step with person_target.gdshader / friendly.gdshader
and RangeTarget in games/target_practice/.
"""

import math
import os
import sys

import bpy  # must come first when Blender runs as a Python package
import bmesh
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from impact_wall_tools import voronoi_fracture  # noqa: E402

THICKNESS = 0.12
# Torso outline (x, z) in meters, counter-clockwise, convex: sloped shoulders.
TORSO = [(-0.30, -0.45), (0.30, -0.45), (0.30, 0.05), (0.18, 0.16), (-0.18, 0.16), (-0.30, 0.05)]
HEAD_CENTER = (0.0, 0.31)
HEAD_RADIUS = 0.15
HEAD_SIDES = 16
TORSO_PIECES = 18
HEAD_PIECES = 6
SEED = 11


def output_path():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    return os.path.abspath(args[0] if args else "person_target.glb")


def make_material(name, color):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = 0.8
    return mat


def add_prism(bm, outline):
    """Add a flat shape (x, z points) extruded THICKNESS along Y, centered on y = 0."""
    front = [bm.verts.new((x, -THICKNESS / 2, z)) for x, z in outline]
    back = [bm.verts.new((x, THICKNESS / 2, z)) for x, z in outline]
    bm.faces.new(list(reversed(front)))  # faces -Y (the front, toward the camera)
    bm.faces.new(back)
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((front[i], front[j], back[j], back[i]))


def head_outline():
    cx, cz = HEAD_CENTER
    return [(cx + HEAD_RADIUS * math.cos(2 * math.pi * k / HEAD_SIDES),
             cz + HEAD_RADIUS * math.sin(2 * math.pi * k / HEAD_SIDES)) for k in range(HEAD_SIDES)]


def mesh_object(name, outlines, material):
    mesh = bpy.data.meshes.new(name)
    bm = bmesh.new()
    for outline in outlines:
        add_prism(bm, outline)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def face_uvs(obj, offset):
    """UV = position on the face in meters, + 0.5."""
    mesh = obj.data
    uv = mesh.uv_layers.get("UVMap") or mesh.uv_layers.new(name="UVMap")
    for loop in mesh.loops:
        co = mesh.vertices[loop.vertex_index].co + offset
        uv.data[loop.index].uv = (co.x + 0.5, co.z + 0.5)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    face = make_material("Face", (0.78, 0.12, 0.1, 1.0))
    inside = make_material("Inside", (0.82, 0.74, 0.6, 1.0))  # raw board, like plywood

    intact = mesh_object("Intact", [TORSO, head_outline()], face)
    face_uvs(intact, Vector())

    # Break the two convex parts separately, then keep only their shards.
    torso = mesh_object("Torso", [TORSO], face)
    head = mesh_object("Head", [head_outline()], face)
    shards = voronoi_fracture(torso, TORSO_PIECES, SEED, 0.5, inside)
    shards += voronoi_fracture(head, HEAD_PIECES, SEED + 1, 0.3, inside)
    for obj in (torso, head):
        bpy.data.objects.remove(obj, do_unlink=True)

    shards_root = bpy.data.objects.new("Shards", None)
    bpy.context.scene.collection.objects.link(shards_root)
    for i, shard in enumerate(shards):
        shard.name = f"Shard_{i:02d}"
        shard.data.name = shard.name
        face_uvs(shard, shard.location)
        shard.parent = shards_root

    path = output_path()
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_yup=True,
                              export_apply=True, export_materials='EXPORT')
    faces = sum(len(s.data.polygons) for s in shards)
    print(f"Wrote {path}: {len(shards)} shards, {faces} faces")


if __name__ == "__main__":
    main()
