using System.Collections.Generic;
using UnityEngine;

namespace MusimusihanRpg.Gameplay
{
    public sealed class DungeonInteractionController : MonoBehaviour
    {
        public WorkshopController Game;
        public DungeonInteractable Focus { get; private set; }
        public DungeonInteractable Active { get; private set; }
        // A host can switch worlds before the previous player is destroyed.
        // Timed owners belong to this controller's player, not the new host player.
        DungeonMotor boundPlayer;
        DungeonMotor Player
        {
            get
            {
                // Inactive trial clones can be used before Awake. Preserve the
                // managed owner reference through destruction for cancellation.
                if(object.ReferenceEquals(boundPlayer,null)&&this!=null)boundPlayer=GetComponent<DungeonMotor>();
                return boundPlayer;
            }
        }
        GUIStyle label;
        readonly List<DungeonInteractable> advancingActors=new List<DungeonInteractable>();
        public void ClearFocus(){Focus=null;}
        public DungeonInteractable RefreshFocus()
        {
            Focus = null;
            if (Player.Eyes == null) return null;
            var eye = Player.Eyes.transform;
            if (Physics.Raycast(eye.position, eye.forward, out var hit, 3, 1 << DungeonInteractable.FocusLayer, QueryTriggerInteraction.Collide))
                Focus = hit.collider.GetComponentInParent<DungeonInteractable>();
            return Focus;
        }
        public bool Interact()
        {
            if (Game.NativeGame?.CampInputBlocked==true || Player.Camping || Game.SimulationPaused || Game.Page != "dungeon") return false;
            if(Game.Combat?.ExecutionActive==true)return false;
            if(Game.Combat?.FindRearTarget()!=null)return (bool)Game.Combat.BeginRearExecution()["accepted"];
            RefreshFocus();
            if (Active != null && Active.Busy)
            {
                if (Active is DungeonTrap trap && trap.Model.State == RuneTrapState.Phase.Disarming) return trap.Interact(Player);
                Cancel(); return false;
            }
            if (Focus == null) return false;
            bool accepted = Focus.Interact(Player); Active = accepted && Focus.Busy ? Focus : null; return accepted;
        }
        public void Cancel() { if (Active != null) Active.Cancel(Player); Player?.ActiveHideoutInteraction?.Cancel(Player); Active = null; }
        void OnDestroy() => Cancel();
        public void Advance(double delta)
        {
            if (Game.SimulationPaused || Game.Page != "dungeon") return;
            RefreshFocus();
            if (Active != null && Active.Busy && Active != Focus && !(Active is LabradorPetting)) Cancel();
            Game.DungeonRoot.GetComponentsInChildren(false,advancingActors);
            foreach (var actor in advancingActors) actor.Advance(delta);
            if (Active != null && !Active.Busy) Active = null;
        }
        void OnGUI()
        {
            if (Game == null || Game.Page != "dungeon" || Game.SimulationPaused || Player.NativeHud) return;
            if (label == null) label = new GUIStyle(GUI.skin.label) { font = Game.KoreanFont, fontSize = 22, alignment = TextAnchor.MiddleCenter, normal = { textColor = Color.white } };
            if (Focus != null) GUI.Label(new Rect(50, Screen.height * .66f, Screen.width - 100, 60), Focus.Prompt, label);
            else if(Game.Combat?.FindRearTarget()!=null)GUI.Label(new Rect(50,Screen.height*.66f,Screen.width-100,60),"E · 검 후방 제압",label);
            if (Active is DungeonChest chest)
                GUI.Label(new Rect(50, Screen.height * .72f, Screen.width - 100, 45), $"{chest.OpeningElapsed:0.0} / {chest.OpeningDuration:0.0}초", label);
            if (Active is DungeonTrap trap && trap.Model.State == RuneTrapState.Phase.Disarming)
            {
                float x = Screen.width * .3f, y = Screen.height * .78f, w = Screen.width * .4f;
                GUI.color = Color.black; GUI.DrawTexture(new Rect(x, y, w, 26), Texture2D.whiteTexture);
                GUI.color = Color.green; GUI.DrawTexture(new Rect(x + w * (float)trap.Model.SuccessStart, y, w * .22f, 26), Texture2D.whiteTexture);
                GUI.color = Color.white; GUI.DrawTexture(new Rect(x + w * (float)trap.Model.NeedleValue - 2, y - 8, 4, 42), Texture2D.whiteTexture);
            }
            GUI.color = Color.white;
        }
    }
}
