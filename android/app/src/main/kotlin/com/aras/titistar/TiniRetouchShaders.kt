package com.aras.titistar

/** GPU preview equations correspond to CropRetouchPixels. No full-frame beauty blur. */
internal object TiniRetouchShaders {
    val vertex =
        """
        attribute vec2 aPosition;
        attribute vec2 aUv;
        uniform mat4 uMatrix;
        varying vec2 vUv;
        void main() { gl_Position = vec4(aPosition, 0.0, 1.0); vUv = (uMatrix * vec4(aUv, 0.0, 1.0)).xy; }
    """
            .trimIndent()
    val external =
        """
        #extension GL_OES_EGL_image_external : require
        precision highp float;
        varying vec2 vUv;
        uniform samplerExternalOES uFrame;
        void main() { gl_FragColor = texture2D(uFrame, vUv); }
    """
            .trimIndent()
    val copy =
        """
        precision highp float;
        varying vec2 vUv;
        uniform sampler2D uFrame;
        void main() { gl_FragColor = texture2D(uFrame, vUv); }
    """
            .trimIndent()
    // Rasterize each detector mask at its current tracked pose. The detector
    // bitmap is top-down; this pass produces a normal bottom-up OpenGL FBO.
    val warpMask =
        """
        precision highp float;
        varying vec2 vUv;
        uniform sampler2D uFrame;
        uniform mat3 uFaceWarp;
        uniform mat3 uMouthWarp;
        uniform vec4 uBounds;
        uniform float uTeethConfidence;
        float inside(vec2 p) {
            return step(uBounds.x,p.x)*step(uBounds.y,p.y)
                *step(p.x,uBounds.z)*step(p.y,uBounds.w);
        }
        void main() {
            vec3 point = vec3(vUv.x,1.0-vUv.y,1.0);
            vec2 face = (uFaceWarp*point).xy;
            vec2 mouth = (uMouthWarp*point).xy;
            vec3 skin = texture2D(uFrame,face).rgb*inside(face);
            float teeth = texture2D(uFrame,mouth).g*inside(mouth)*uTeethConfidence;
            gl_FragColor = vec4(skin.r,teeth,skin.b,1.0);
        }
    """
            .trimIndent()
    val blur =
        """
        precision highp float;
        varying vec2 vUv;
        uniform sampler2D uFrame;
        uniform sampler2D uMask;
        uniform vec2 uStep;
        void main() {
            float radius = floor(texture2D(uMask, vUv).b * 12.0 + 0.5);
            if (radius < 0.5) { gl_FragColor = texture2D(uFrame, vUv); return; }
            float sigma = radius * (2.0/3.0);
            vec4 sum = vec4(0.0); float total = 0.0;
            for (int i = -12; i <= 12; i++) {
                float f = float(i);
                if (abs(f) <= radius) {
                    float weight = exp(-(f*f)/(2.0*sigma*sigma));
                    sum += texture2D(uFrame, vUv + uStep*f)*weight;
                    total += weight;
                }
            }
            gl_FragColor = sum / max(total, 0.00001);
        }
    """
            .trimIndent()
    val retouch =
        """
        precision highp float;
        varying vec2 vUv;
        uniform sampler2D uFrame;
        uniform sampler2D uSoft;
        uniform sampler2D uMask;
        uniform float uSmooth;
        uniform float uTeeth;
        uniform float uMaskEnabled;
        void main() {
            vec4 source = texture2D(uFrame, vUv);
            if (uMaskEnabled < 0.5 || (uSmooth <= 0.0 && uTeeth <= 0.0)) {
                gl_FragColor = source; return;
            }
            vec3 mask = texture2D(uMask, vUv).rgb;
            vec3 c = source.rgb * 255.0;
            vec3 result = source.rgb;
            if (uSmooth > 0.0 && mask.r > 0.0) {
                vec3 soft = texture2D(uSoft, vUv).rgb;
                float cb = 128.0 - .168736*c.r - .331264*c.g + .5*c.b;
                float cr = 128.0 + .5*c.r - .418688*c.g - .081312*c.b;
                float skin = smoothstep(70.0,88.0,cb)*(1.0-smoothstep(135.0,150.0,cb))
                    *smoothstep(120.0,135.0,cr)*(1.0-smoothstep(178.0,195.0,cr));
                vec3 delta = abs(source.rgb-soft)*255.0;
                float d = (delta.r+delta.g+delta.b)/3.0;
                float edge = exp(-(d*d)/(2.0*36.0*36.0));
                result += (soft-source.rgb)*(uSmooth*.9*skin*mask.r*edge);
            }
            if (uTeeth > 0.0 && mask.g > 0.0) {
                float hi = max(c.r,max(c.g,c.b)), lo = min(c.r,min(c.g,c.b));
                float luma = dot(c,vec3(.2126,.7152,.0722));
                float neutral = 1.0-smoothstep(.22,.48,(hi-lo)/max(1.0,hi));
                float notRed = 1.0-smoothstep(18.0,42.0,c.r-c.g);
                float amount = uTeeth*neutral*notRed*smoothstep(75.0,140.0,luma)*mask.g;
                float target = (luma+(255.0-luma)*.38)/255.0;
                result += (vec3(target)-source.rgb)*amount;
            }
            gl_FragColor = vec4(clamp(result,0.0,1.0),source.a);
        }
    """
            .trimIndent()
}
