#version 330 core
// Fullscreen quad for the volume pass. The fragment stage derives the pixel
// from gl_FragCoord, so positions are all it needs.
layout (location = 0) in vec2 aPos;

void main() {
    gl_Position = vec4(aPos, 0.0, 1.0);
}
