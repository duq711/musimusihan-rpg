using System;
using System.Collections.Generic;
using UnityEngine;

namespace MusimusihanRpg.Gameplay
{
    /// <summary>Samples the supplied Generic clips on the supplied dog; blends each change of action.</summary>
    public sealed class PetAnimationPlayer
    {
        readonly GameObject model;
        readonly Dictionary<string, AnimationClip> clips = new Dictionary<string, AnimationClip>();
        readonly Transform[] bones;
        Vector3[] entryPosition, entryScale;
        Quaternion[] entryRotation;
        string current = "";
        float clock, blend;
        public string Current => current;
        public float Time => clock;
        public PetAnimationPlayer(GameObject model, AnimationClip[] supplied)
        {
            this.model = model;
            foreach (var animator in model.GetComponentsInChildren<Animator>(true)) animator.enabled = false;
            foreach (var animation in model.GetComponentsInChildren<Animation>(true)) animation.enabled = false;
            foreach (var clip in supplied ?? Array.Empty<AnimationClip>()) if (clip != null) clips[clip.name] = clip;
            bones = model.GetComponentsInChildren<Transform>(true);
            entryPosition = new Vector3[bones.Length]; entryScale = new Vector3[bones.Length]; entryRotation = new Quaternion[bones.Length];
        }
        public bool Has(string name) => clips.ContainsKey(name);
        public float Duration(string name, float fallback) => clips.TryGetValue(name, out var clip) ? Mathf.Max(.01f, clip.length) : fallback;
        public void Advance(string name, double delta, bool loop = true, float rate = 1)
        {
            if (!clips.TryGetValue(name, out var clip)) return;
            if (name != current)
            {
                for (int i = 0; i < bones.Length; i++) { entryPosition[i] = bones[i].localPosition; entryScale[i] = bones[i].localScale; entryRotation[i] = bones[i].localRotation; }
                current = name; clock = blend = 0;
            }
            clock += (float)delta * rate; blend += (float)delta;
            float time = loop ? clock % Mathf.Max(.01f, clip.length) : Mathf.Min(clock, clip.length);
            clip.SampleAnimation(model, time);
            if (blend < .18f)
            {
                float weight = Mathf.SmoothStep(0, 1, blend / .18f);
                for (int i = 0; i < bones.Length; i++)
                {
                    bones[i].localPosition = Vector3.Lerp(entryPosition[i], bones[i].localPosition, weight);
                    bones[i].localRotation = Quaternion.Slerp(entryRotation[i], bones[i].localRotation, weight);
                    bones[i].localScale = Vector3.Lerp(entryScale[i], bones[i].localScale, weight);
                }
            }
        }
    }
}
