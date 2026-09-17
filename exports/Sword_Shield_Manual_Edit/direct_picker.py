"""Direct finger picking for the existing editable sword/shield rigs."""
import bpy
from bpy_extras import view3d_utils

def select_hit(context, origin, direction):
    """Pick the nearest visible hand surface, then its strongest skin joint."""
    depsgraph=context.evaluated_depsgraph_get()
    hits=[]
    for obj in context.scene.objects:
        if obj.type!='MESH' or not (obj.get('editor_hand') or obj.get('editor_equipment')) or not obj.visible_get():
            continue
        evaluated=obj.evaluated_get(depsgraph)
        inverse=evaluated.matrix_world.inverted()
        local_origin=inverse@origin
        local_direction=(inverse.to_3x3()@direction).normalized()
        hit, point, normal, face=evaluated.ray_cast(local_origin,local_direction)
        if not hit or face<0:
            continue
        vertices=evaluated.data.polygons[face].vertices
        vertex=min((evaluated.data.vertices[i] for i in vertices),key=lambda v:(v.co-point).length_squared)
        weights=[(g.weight,obj.vertex_groups[g.group].name) for g in vertex.groups]
        rigs=[m.object for m in obj.modifiers if m.type=='ARMATURE' and m.object and m.object.get('grip_editor')]
        if not rigs:
            continue
        rig=rigs[0]
        weights=[(w,n) for w,n in weights if n in rig.pose.bones]
        if weights:
            hits.append(((evaluated.matrix_world@point-origin).length,rig,max(weights)[1]))
    if not hits:
        return None
    _,rig,name=min(hits,key=lambda h:h[0])
    if context.object and context.object.mode!='OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')
    bpy.ops.object.select_all(action='DESELECT')
    rig.select_set(True);context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='POSE')
    for bone in rig.pose.bones:
        bone.select=False
    rig.pose.bones[name].select=True
    rig.data.bones.active=rig.data.bones[name]
    context.scene['editor_side']=rig['editor_side']
    return name

class GRIP_OT_surface_pick(bpy.types.Operator):
    bl_idname='grip_edit.surface_pick'
    bl_label='손가락 직접 선택'
    bl_description='손가락 표면을 두 번 클릭하여 해당 마디를 선택하고 회전합니다'
    @classmethod
    def poll(cls,context):
        return context.area and context.area.type=='VIEW_3D' and any(o.get('grip_editor') for o in context.scene.objects)
    def invoke(self,context,event):
        if context.region.type!='WINDOW':
            return {'PASS_THROUGH'}
        xy=(event.mouse_region_x,event.mouse_region_y)
        origin=view3d_utils.region_2d_to_origin_3d(context.region,context.region_data,xy)
        direction=view3d_utils.region_2d_to_vector_3d(context.region,context.region_data,xy)
        if not select_hit(context,origin,direction):
            return {'PASS_THROUGH'}
        bpy.ops.wm.tool_set_by_id(name='builtin.transform' if context.active_pose_bone.name=='equipment_adjust' else 'builtin.rotate')
        context.space_data.show_gizmo=True
        context.area.tag_redraw()
        return {'FINISHED'}

class GRIP_PT_direct(bpy.types.Panel):
    bl_label='마우스로 직접 조정'
    bl_space_type='VIEW_3D';bl_region_type='UI';bl_category='양손 편집';bl_order=-10
    @classmethod
    def poll(cls,context):return any(o.get('grip_editor') for o in context.scene.objects)
    def draw(self,context):
        self.layout.label(text='손가락 표면 더블클릭 → 마디 선택')
        self.layout.label(text='색 조절봉은 한 번 클릭해도 됩니다')
        self.layout.label(text='회전 고리 드래그 또는 R → 마우스')
        self.layout.label(text='클릭 확정 / Esc 취소 / Ctrl+Z 되돌리기')

def install():
    for cls in (GRIP_OT_surface_pick,GRIP_PT_direct):
        old=getattr(bpy.types,cls.__name__,None)
        if old:bpy.utils.unregister_class(old)
        bpy.utils.register_class(cls)
    config=bpy.context.window_manager.keyconfigs.addon
    if config:
        for mode in ('Pose','Object Mode'):
            km=config.keymaps.new(name=mode,space_type='EMPTY')
            for item in list(km.keymap_items):
                if item.idname=='grip_edit.surface_pick':km.keymap_items.remove(item)
            km.keymap_items.new('grip_edit.surface_pick','LEFTMOUSE','DOUBLE_CLICK')
    for obj in bpy.context.scene.objects:
        if obj.type=='ARMATURE' and obj.get('grip_editor'):
            obj.show_in_front=True
            obj.data.display_type='OCTAHEDRAL'
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.show_gizmo=True
                with bpy.context.temp_override(window=window,area=area):
                    bpy.ops.wm.tool_set_by_id(name='builtin.rotate')

install()
