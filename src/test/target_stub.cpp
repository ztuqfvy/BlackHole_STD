// Stub translation unit for targets whose real main is platform-specific.
//
// swz-bh-realtime-metal's real main is src/Swz_Realtime_Metal.mm
// (Objective-C++/Metal). mcpp does not let a cfg-selector row *define* a bin
// target, only override its main — so non-macOS targets override main to this
// file instead. The program is never meant to run there; it exists so the
// target parses and the build proceeds to the sources that matter.
int main() { return 0; }
