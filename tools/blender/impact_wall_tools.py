bl_info = {
    "name": "Impact Wall Tools",
    "author": "Impact Wall team",
    "version": (1, 0, 0),
    "blender": (4, 2, 0),
    "location": "3D Viewport > Sidebar (press N) > Impact Wall",
    "description": "One-click origin and transform fixes with plain-language tips, "
                   "plus a shatter tool for making game pieces.",
    "category": "Object",
}

# How to install (once):
#   Edit > Preferences > Add-ons > the small arrow (top right) > Install from Disk...
#   pick this file, then tick the checkbox next to "Impact Wall Tools".
# Then in the 3D view press N and click the "Impact Wall" tab.
#
# The fracture code below is also used by make_target_shards.py to build the
# game's shattering target, so the button and the script give the same result.

import random

import bpy  # must come first when Blender runs as a Python package
import bmesh
from mathutils import Vector


# ---------------------------------------------------------------------------
# Fracture (Voronoi): split a mesh into irregular shards, like a real break.
# ---------------------------------------------------------------------------

def _seed_points(lo, hi, count, rng, center_bias, flat_axis):
    """Random break points inside the box lo..hi.

    center_bias (0..1) is the share of points clustered near the middle, which
    gives small shards at the center and bigger ones toward the edges, like a
    real impact. flat_axis (0, 1, 2 or None) keeps every point on the middle
    of that axis, so a thin board breaks into pieces that go all the way
    through it.
    """
    center = (lo + hi) / 2.0
    size = hi - lo
    points = []
    for _ in range(count):
        if rng.random() < center_bias:
            p = Vector([rng.gauss(center[i], size[i] * 0.15) for i in range(3)])
        else:
            p = Vector([rng.uniform(lo[i], hi[i]) for i in range(3)])
        for i in range(3):
            p[i] = min(max(p[i], lo[i] + size[i] * 0.02), hi[i] - size[i] * 0.02)
        if flat_axis is not None:
            p[flat_axis] = center[flat_axis]
        points.append(p)
    return points


def voronoi_fracture(obj, count=24, seed=1, center_bias=0.5, inside_material=None):
    """Split a mesh object into `count` shards. Returns the new shard objects.

    Works on convex shapes (boxes, boards, slabs, bottles without holes).
    Faces created by the cuts get `inside_material` (added to each shard).
    The original object is left untouched; hide or delete it yourself.
    """
    rng = random.Random(seed)
    src = bmesh.new()
    src.from_mesh(obj.data)
    lo = Vector([min(v.co[i] for v in src.verts) for i in range(3)])
    hi = Vector([max(v.co[i] for v in src.verts) for i in range(3)])
    size = hi - lo
    thinnest = min(range(3), key=lambda i: size[i])
    flat_axis = thinnest if size[thinnest] < 0.4 * max(size) else None
    points = _seed_points(lo, hi, count, rng, center_bias, flat_axis)

    materials = list(obj.data.materials)
    inside_index = None
    if inside_material is not None:
        if inside_material not in materials:
            materials.append(inside_material)
        inside_index = materials.index(inside_material)

    shards = []
    for i, p in enumerate(points):
        bm = src.copy()
        for j, q in enumerate(points):
            if i == j or (q - p).length < 1e-6:
                continue
            geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
            result = bmesh.ops.bisect_plane(
                bm, geom=geom, dist=1e-6, plane_co=(p + q) / 2.0,
                plane_no=(q - p).normalized(), clear_outer=True)
            cut_edges = [e for e in result["geom_cut"] if isinstance(e, bmesh.types.BMEdge)]
            if len(cut_edges) >= 3:
                made = bmesh.ops.contextual_create(bm, geom=cut_edges)
                for f in made["faces"]:
                    if inside_index is not None:
                        f.material_index = inside_index
        if len(bm.verts) < 4 or len(bm.faces) < 4:
            bm.free()
            continue
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])

        # Put each shard's origin at its own middle, so it spins naturally.
        middle = sum((v.co for v in bm.verts), Vector()) / len(bm.verts)
        for v in bm.verts:
            v.co -= middle

        mesh = bpy.data.meshes.new(f"{obj.name}_shard_{i:02d}")
        bm.to_mesh(mesh)
        bm.free()
        for m in materials:
            mesh.materials.append(m)
        shard = bpy.data.objects.new(mesh.name, mesh)
        shard.matrix_world = obj.matrix_world.copy()
        shard.location = obj.matrix_world @ middle
        for col in obj.users_collection:
            col.objects.link(shard)
        shards.append(shard)
    src.free()
    return shards


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _world_bounds(obj):
    corners = [obj.matrix_world @ Vector(c) for c in obj.bound_box]
    lo = Vector([min(c[i] for c in corners) for i in range(3)])
    hi = Vector([max(c[i] for c in corners) for i in range(3)])
    return lo, hi


def _set_origin_to(context, obj, point):
    """Move obj's origin to `point` (world space) without moving its shape."""
    cursor = context.scene.cursor
    saved = cursor.location.copy()
    cursor.location = point
    with context.temp_override(selected_editable_objects=[obj], active_object=obj, object=obj):
        bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    cursor.location = saved


def _selected_meshes(context):
    return [o for o in context.selected_objects if o.type == 'MESH']


class _ObjectModeOperator(bpy.types.Operator):
    bl_options = {'REGISTER', 'UNDO'}

    @classmethod
    def poll(cls, context):
        return context.mode == 'OBJECT' and bool(context.selected_objects)


# ---------------------------------------------------------------------------
# Origin and transform buttons
# ---------------------------------------------------------------------------

class IW_OT_apply_rot_scale(_ObjectModeOperator):
    bl_idname = "impact_wall.apply_rot_scale"
    bl_label = "Apply Rotation & Scale"
    bl_description = ("Make the current size and rotation the object's new 'normal', "
                      "so scale shows 1 and rotation shows 0. Do this before exporting "
                      "or fracturing, or physics and shading can come out wrong")

    def execute(self, context):
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        self.report({'INFO'}, "Rotation and scale applied")
        return {'FINISHED'}


class IW_OT_origin_center(_ObjectModeOperator):
    bl_idname = "impact_wall.origin_center"
    bl_label = "Origin to Center"
    bl_description = ("Move the orange dot (the origin, the point it spins and scales "
                      "around) to the middle of the object. The shape doesn't move")

    def execute(self, context):
        bpy.ops.object.origin_set(type='ORIGIN_GEOMETRY', center='BOUNDS')
        return {'FINISHED'}


class IW_OT_origin_bottom(_ObjectModeOperator):
    bl_idname = "impact_wall.origin_bottom"
    bl_label = "Origin to Bottom"
    bl_description = ("Move the origin to the bottom-middle of the object. Best for "
                      "things that stand on a floor or shelf (targets, blocks, bottles)")

    def execute(self, context):
        for obj in _selected_meshes(context):
            lo, hi = _world_bounds(obj)
            _set_origin_to(context, obj, Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z)))
        return {'FINISHED'}


class IW_OT_origin_cursor(_ObjectModeOperator):
    bl_idname = "impact_wall.origin_cursor"
    bl_label = "Origin to 3D Cursor"
    bl_description = ("Move the origin to the 3D cursor (the red-and-white ring). "
                      "Shift + right-click in the view to place the cursor first")

    def execute(self, context):
        bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        return {'FINISHED'}


class IW_OT_drop_to_floor(_ObjectModeOperator):
    bl_idname = "impact_wall.drop_to_floor"
    bl_label = "Sit on Floor"
    bl_description = "Move the object up or down so its lowest point touches the floor (Z = 0)"

    def execute(self, context):
        for obj in context.selected_objects:
            lo, _hi = _world_bounds(obj)
            obj.location.z -= lo.z
        return {'FINISHED'}


class IW_OT_center_world(_ObjectModeOperator):
    bl_idname = "impact_wall.center_world"
    bl_label = "Move to World Center"
    bl_description = "Move the object so its origin sits at the center of the world (0, 0, 0)"

    def execute(self, context):
        for obj in context.selected_objects:
            obj.location = (0.0, 0.0, 0.0)
        return {'FINISHED'}


class IW_OT_cursor_reset(bpy.types.Operator):
    bl_idname = "impact_wall.cursor_reset"
    bl_label = "Reset 3D Cursor"
    bl_description = "Put the 3D cursor back at the center of the world"
    bl_options = {'REGISTER', 'UNDO'}

    def execute(self, context):
        context.scene.cursor.location = (0.0, 0.0, 0.0)
        context.scene.cursor.rotation_euler = (0.0, 0.0, 0.0)
        return {'FINISHED'}


# ---------------------------------------------------------------------------
# Shatter button
# ---------------------------------------------------------------------------

class IW_OT_fracture(_ObjectModeOperator):
    bl_idname = "impact_wall.fracture"
    bl_label = "Shatter Selected"
    bl_description = ("Break the selected object into irregular shards for the game. "
                      "The original is hidden, not deleted. Ctrl+Z undoes it")

    pieces: bpy.props.IntProperty(name="Pieces", default=24, min=4, max=40,
                                  description="How many shards. Keep it 30 or under for phones")
    seed: bpy.props.IntProperty(name="Variation", default=1, min=0,
                                description="Change this number for a different break pattern")
    center_bias: bpy.props.FloatProperty(name="Small pieces in middle", default=0.5, min=0.0, max=1.0,
                                         description="Higher = more small shards near the center")

    def execute(self, context):
        inside = bpy.data.materials.get("Inside") or bpy.data.materials.new("Inside")
        made = 0
        for obj in _selected_meshes(context):
            if any(abs(s - 1.0) > 1e-4 for s in obj.scale):
                self.report({'WARNING'}, f"{obj.name}: apply rotation & scale first")
                continue
            shards = voronoi_fracture(obj, self.pieces, self.seed, self.center_bias, inside)
            obj.hide_set(True)
            made += len(shards)
        self.report({'INFO'}, f"Made {made} shards")
        return {'FINISHED'}


# ---------------------------------------------------------------------------
# The sidebar panel
# ---------------------------------------------------------------------------

def _tip(layout, text):
    for line in text.split("\n"):
        row = layout.row()
        row.scale_y = 0.7
        row.label(text=line)


class IW_PT_panel(bpy.types.Panel):
    bl_label = "Impact Wall"
    bl_idname = "IW_PT_panel"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "Impact Wall"

    def draw(self, context):
        layout = self.layout
        scene = context.scene
        tips = scene.impact_wall_show_tips
        layout.prop(scene, "impact_wall_show_tips", text="Show tips")
        obj = context.active_object

        # --- What's selected, and is anything wrong with it? ---
        box = layout.box()
        if context.mode != 'OBJECT':
            box.label(text="Press Tab to go back to Object Mode", icon='INFO')
            return
        if obj is None:
            box.label(text="Click an object to select it", icon='INFO')
            return
        box.label(text=obj.name, icon='OBJECT_DATA')
        scale_ok = all(abs(s - 1.0) < 1e-4 for s in obj.scale)
        rot_ok = all(abs(r) < 1e-4 for r in obj.rotation_euler)
        if scale_ok and rot_ok:
            box.label(text="Rotation & scale are clean", icon='CHECKMARK')
        else:
            if not scale_ok:
                box.label(text="Scale isn't 1: click Apply below", icon='ERROR')
            if not rot_ok:
                box.label(text="Rotated: Apply if this is its resting pose", icon='ERROR')

        # --- Origin (the orange dot) ---
        col = layout.box().column(align=True)
        col.label(text="Origin (the orange dot)", icon='PIVOT_CURSOR')
        if tips:
            _tip(col, "It's the point the object moves,\nspins and scales around.")
        col.operator(IW_OT_origin_center.bl_idname, icon='PIVOT_BOUNDBOX')
        col.operator(IW_OT_origin_bottom.bl_idname, icon='TRIA_DOWN_BAR')
        col.operator(IW_OT_origin_cursor.bl_idname, icon='PIVOT_CURSOR')
        col.operator(IW_OT_cursor_reset.bl_idname, icon='ORIENTATION_CURSOR')

        # --- Transforms ---
        col = layout.box().column(align=True)
        col.label(text="Position, rotation & scale", icon='OBJECT_ORIGIN')
        if tips:
            _tip(col, "Resized or rotated it? Click Apply\nso the game sees the real shape.")
        col.operator(IW_OT_apply_rot_scale.bl_idname, icon='CHECKMARK')
        col.operator(IW_OT_drop_to_floor.bl_idname, icon='ANCHOR_BOTTOM')
        col.operator(IW_OT_center_world.bl_idname, icon='WORLD')

        # --- Shatter ---
        col = layout.box().column(align=True)
        col.label(text="Shatter (game pieces)", icon='MOD_EXPLODE')
        if tips:
            _tip(col, "Apply rotation & scale first.\nAdjust pieces in the pop-up at\nthe bottom-left after clicking.")
        col.operator(IW_OT_fracture.bl_idname, icon='MOD_EXPLODE')

        if tips:
            col = layout.box().column(align=True)
            col.label(text="Handy keys", icon='EVENT_TAB')
            _tip(col, "G move   R rotate   S scale\n"
                      "Then X / Y / Z to lock an axis\n"
                      "Ctrl+A  apply menu\n"
                      "Shift+right-click  place 3D cursor\n"
                      "Numpad .  zoom to selected\n"
                      "Ctrl+Z  undo")


CLASSES = (
    IW_OT_apply_rot_scale,
    IW_OT_origin_center,
    IW_OT_origin_bottom,
    IW_OT_origin_cursor,
    IW_OT_drop_to_floor,
    IW_OT_center_world,
    IW_OT_cursor_reset,
    IW_OT_fracture,
    IW_PT_panel,
)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Scene.impact_wall_show_tips = bpy.props.BoolProperty(
        name="Show tips", default=True, description="Show short explanations in this panel")


def unregister():
    del bpy.types.Scene.impact_wall_show_tips
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
