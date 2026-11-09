# Locally generated prologue animation pack

These Kimodo SOMA RP v1.1 motions are experimental and stored separately from the licensed Motifect source clips. The motion model is released under the [NVIDIA Open Model License](https://www.nvidia.com/en-us/agreements/enterprise-software/nvidia-open-model-license/); see the [SOMA RP v1.1 model card](https://huggingface.co/nvidia/Kimodo-SOMA-RP-v1.1). This pack contains generated motion outputs only, not the model weights or text encoder. Each GLB contains a skeleton and animation, not a character mesh. The character preview retargets them onto the currently available VRM model.

## Preview

1. Open `experiments/character_preview/language_life_prototype.tscn` and run it with F6.
2. Press F7 to open the animation browser.
3. Select `Generated — A-01 / Комната` or `Generated — A-02 / Завтрак`, choose a segment, and press `Проиграть`.

The clips are separate segments, not a continuous cutscene. Each includes five transition frames from Kimodo; inspect its start and end on the preview model. No key, counter, bread, or other prop is included in the animation. The preview does not perform item synchronisation.

## Segments

| Pack | Clip | Frames | Prompt |
| --- | --- | ---: | --- |
| A-02 / Завтрак | 1. Завтрак — обычное движение | 140 | An adult woman standing at a kitchen counter makes small, natural breakfast-preparation motions with both hands at waist level, briefly leans forward to check the counter and returns to a relaxed working stance. Subtle realistic motions, calm pace, feet planted, no visible props, no walking, no exaggerated stirring. |
| A-02 / Завтрак | 2. Обратить внимание и указать | 115 | An adult woman standing at a kitchen counter pauses a small hand task, raises the head and turns the upper body slightly toward another person, then makes a short clear open-hand indication toward a nearby shelf, and finishes in a neutral attentive standing pose. Gentle conversational timing, feet planted, no object in hands, no walking. |
| A-02 / Завтрак | 3. Вернуться к завтраку | 105 | An adult woman standing at a kitchen counter gives a small acknowledging nod, turns attention back to the counter, lowers both hands into a relaxed working position, and resumes gentle small breakfast-preparation motions. Natural unhurried timing, planted feet, no props, no walking. |
| A-01 / Комната | 1. Пригласить в комнату | 120 | A friendly adult woman standing beside a doorway pauses, looks toward the room to one side, makes a restrained open-hand gesture inviting someone to enter, then returns to a relaxed neutral standing pose. Natural everyday timing, feet planted, subtle head turn, no walking, no exaggerated acting. |
| A-01 / Комната | 2. Положить ключ | 105 | A friendly adult woman stands next to a waist-height table, gently extends one hand as if setting down a very small object on the tabletop, briefly looks at the spot, withdraws the hand, and settles into a relaxed neutral standing pose. Feet stay planted, realistic shoulder and elbow motion, no prop modeled, no walking. |

Generated GLBs use Kimodo job IDs in their filenames so later output cannot silently overwrite an earlier generation.
