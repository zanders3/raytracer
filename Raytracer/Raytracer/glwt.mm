//
//  GLWT v2.0
//  by Alex Parker
//  A two file OpenGL 3.2+ Window Opener and Library Loader for OSX
//  Public Domain License
//

#include "glwt.h"

#ifdef __APPLE__

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#include <mach/mach_time.h>

//GLView header
@interface GLView : NSOpenGLView<NSWindowDelegate>
{
    uint64_t lastFrame;
    mach_timebase_info_data_t info;
}
@end

//GLView implementation
NSTimer* timer;

extern "C" {
    extern void glSwapAPPLE(void);
}

@implementation GLView

- (void)renderTimerCallback:(NSTimer*)timer
{
    // lets the OS call drawRect for best window system synchronization
    [self display];
}

-(id)initWithFrame:(NSRect)frameRect pixelFormat:(NSOpenGLPixelFormat *)format
{
    self = [super initWithFrame:frameRect pixelFormat:format];
    
    //ensure vbsynch is on!
    [[self openGLContext] setValues:(GLint[]){1} forParameter:NSOpenGLCPSwapInterval];
    
    lastFrame = mach_absolute_time();
    mach_timebase_info(&info);
    
    timer = [NSTimer timerWithTimeInterval:0.001
                                    target:self
                                  selector:@selector(renderTimerCallback:)
                                  userInfo:nil
                                   repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSDefaultRunLoopMode];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSModalPanelRunLoopMode];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowWillClose:) name:NSWindowWillCloseNotification object:self.window];
    
    return self;
}

-(void)windowWillClose:(NSNotification*)notification
{
    [NSApp terminate:nil];
}

-(void)drawRect:(NSRect)dirtyRect
{
    uint64_t latestTime = mach_absolute_time();
    uint64_t elapsed = latestTime - lastFrame;
    lastFrame = latestTime;
    
    elapsed *= info.numer;
    elapsed /= info.denom;
    
    float elapsedSeconds = (float)elapsed * 0.000000001f;
    
    draw(elapsedSeconds);
    
    glSwapAPPLE();
}

@end

int initglwt(const char* title, int width, int height, bool fullscreen)
{
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    id menubar = [NSMenu new];
    id appMenuItem = [NSMenuItem new];
    [menubar addItem:appMenuItem];
    [NSApp setMainMenu:menubar];
    id appMenu = [NSMenu new];
    id quitMenuItem = [[NSMenuItem alloc] initWithTitle:@"Quit"
                                                  action:@selector(terminate:) keyEquivalent:@"q"];
    [appMenu addItem:quitMenuItem];
    [appMenuItem setSubmenu:appMenu];
    
    NSRect screenSize = [[NSScreen mainScreen] frame];
    NSRect mainDisplayRect = NSMakeRect((screenSize.size.width-width)/2, (screenSize.size.height-height)/2, width, height);
    id window = [[NSWindow alloc]
                 initWithContentRect:mainDisplayRect
                 styleMask:NSTitledWindowMask|NSClosableWindowMask
                 backing:NSBackingStoreBuffered
                 defer:YES];
    //[window cascadeTopLeftFromPoint:NSMakePoint(20,20)];
    [window setTitle:[NSString stringWithUTF8String:title]];
    [window makeKeyAndOrderFront:nil];
    [window setOpaque:YES];
    [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
    
    if (fullscreen)
        [window toggleFullScreen:nil];
    
    //Request an OpenGL 3.2 context (bleurgh... horrible. wtf apple)
    CGLPixelFormatAttribute attribs[] =
    {
        kCGLPFAOpenGLProfile, (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
        kCGLPFAAccelerated,
        kCGLPFANoRecovery,
        kCGLPFAColorSize, (CGLPixelFormatAttribute)24,
        kCGLPFADepthSize, (CGLPixelFormatAttribute)16,
        kCGLPFADoubleBuffer,
        (CGLPixelFormatAttribute)0
    };
    CGLPixelFormatObj cglPixelFormat = NULL;
    GLint numPixelFormats;
    CGLChoosePixelFormat (attribs, &cglPixelFormat, &numPixelFormats);
    
    NSOpenGLPixelFormat* pixelFormat = [[NSOpenGLPixelFormat alloc] initWithCGLPixelFormatObj:cglPixelFormat];
    NSRect viewRect = NSMakeRect(0.0, 0.0, mainDisplayRect.size.width, mainDisplayRect.size.height);
    GLView *fullScreenView = [[GLView alloc] initWithFrame:viewRect pixelFormat: pixelFormat];
    
    // Synchronize buffer swaps with vertical refresh rate
    GLint swapInt = 1;
    [[fullScreenView openGLContext] setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];
    
    //Load Open GL functions
    if (gl3wInit()) {
        fprintf(stderr, "failed to initialize OpenGL\n");
        return -1;
    }
    if (!gl3wIsSupported(3, 2)) {
        fprintf(stderr, "OpenGL 3.2 not supported\n");
        return -1;
    }
    printf("OpenGL %s, GLSL %s\n", glGetString(GL_VERSION), glGetString(GL_SHADING_LANGUAGE_VERSION));
    
    //Add the OpenGL view to the window
    [window setContentView: fullScreenView];

    setup();
    
    [NSApp run];
    
    return 0;
}

#endif //__APPLE__

//gl3w library follows

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN 1
#include <windows.h>

static HMODULE libgl;

static void open_libgl(void)
{
    libgl = LoadLibraryA("opengl32.dll");
}

static void close_libgl(void)
{
    FreeLibrary(libgl);
}

static void *get_proc(const char *proc)
{
    void *res;
    
    res = wglGetProcAddress(proc);
    if (!res)
        res = GetProcAddress(libgl, proc);
    return res;
}
#elif defined(__APPLE__) || defined(__APPLE_CC__)
#include <Carbon/Carbon.h>

CFBundleRef bundle;
CFURLRef bundleURL;

static void open_libgl(void)
{
    bundleURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                              CFSTR("/System/Library/Frameworks/OpenGL.framework"),
                                              kCFURLPOSIXPathStyle, true);
    
    bundle = CFBundleCreate(kCFAllocatorDefault, bundleURL);
    assert(bundle != NULL);
}

static void close_libgl(void)
{
    CFRelease(bundle);
    CFRelease(bundleURL);
}

static void *get_proc(const char *proc)
{
    void *res;
    
    CFStringRef procname = CFStringCreateWithCString(kCFAllocatorDefault, proc,
                                                     kCFStringEncodingASCII);
    res = CFBundleGetFunctionPointerForName(bundle, procname);
    CFRelease(procname);
    return res;
}
#else
#include <dlfcn.h>
#include <GL/glx.h>

static void *libgl;

static void open_libgl(void)
{
    libgl = dlopen("libGL.so.1", RTLD_LAZY | RTLD_GLOBAL);
}

static void close_libgl(void)
{
    dlclose(libgl);
}

static void *get_proc(const char *proc)
{
    void *res;
    
    res = glXGetProcAddress((const GLubyte *) proc);
    if (!res)
        res = dlsym(libgl, proc);
    return res;
}
#endif

static struct {
    int major, minor;
} version;

static int parse_version(void)
{
    if (!glGetIntegerv)
        return -1;
    
    glGetIntegerv(GL_MAJOR_VERSION, &version.major);
    glGetIntegerv(GL_MINOR_VERSION, &version.minor);
    
    if (version.major < 3)
        return -1;
    return 0;
}

static void load_procs(void);

int gl3wInit(void)
{
    open_libgl();
    load_procs();
    close_libgl();
    return parse_version();
}

int gl3wIsSupported(int major, int minor)
{
    if (major < 3)
        return 0;
    if (version.major == major)
        return version.minor >= minor;
    return version.major >= major;
}

void *gl3wGetProcAddress(const char *proc)
{
    return get_proc(proc);
}

PFNGLCULLFACEPROC gl3wCullFace;
PFNGLFRONTFACEPROC gl3wFrontFace;
PFNGLHINTPROC gl3wHint;
PFNGLLINEWIDTHPROC gl3wLineWidth;
PFNGLPOINTSIZEPROC gl3wPointSize;
PFNGLPOLYGONMODEPROC gl3wPolygonMode;
PFNGLSCISSORPROC gl3wScissor;
PFNGLTEXPARAMETERFPROC gl3wTexParameterf;
PFNGLTEXPARAMETERFVPROC gl3wTexParameterfv;
PFNGLTEXPARAMETERIPROC gl3wTexParameteri;
PFNGLTEXPARAMETERIVPROC gl3wTexParameteriv;
PFNGLTEXIMAGE1DPROC gl3wTexImage1D;
PFNGLTEXIMAGE2DPROC gl3wTexImage2D;
PFNGLDRAWBUFFERPROC gl3wDrawBuffer;
PFNGLCLEARPROC gl3wClear;
PFNGLCLEARCOLORPROC gl3wClearColor;
PFNGLCLEARSTENCILPROC gl3wClearStencil;
PFNGLCLEARDEPTHPROC gl3wClearDepth;
PFNGLSTENCILMASKPROC gl3wStencilMask;
PFNGLCOLORMASKPROC gl3wColorMask;
PFNGLDEPTHMASKPROC gl3wDepthMask;
PFNGLDISABLEPROC gl3wDisable;
PFNGLENABLEPROC gl3wEnable;
PFNGLFINISHPROC gl3wFinish;
PFNGLFLUSHPROC gl3wFlush;
PFNGLBLENDFUNCPROC gl3wBlendFunc;
PFNGLLOGICOPPROC gl3wLogicOp;
PFNGLSTENCILFUNCPROC gl3wStencilFunc;
PFNGLSTENCILOPPROC gl3wStencilOp;
PFNGLDEPTHFUNCPROC gl3wDepthFunc;
PFNGLPIXELSTOREFPROC gl3wPixelStoref;
PFNGLPIXELSTOREIPROC gl3wPixelStorei;
PFNGLREADBUFFERPROC gl3wReadBuffer;
PFNGLREADPIXELSPROC gl3wReadPixels;
PFNGLGETBOOLEANVPROC gl3wGetBooleanv;
PFNGLGETDOUBLEVPROC gl3wGetDoublev;
PFNGLGETERRORPROC gl3wGetError;
PFNGLGETFLOATVPROC gl3wGetFloatv;
PFNGLGETINTEGERVPROC gl3wGetIntegerv;
PFNGLGETSTRINGPROC gl3wGetString;
PFNGLGETTEXIMAGEPROC gl3wGetTexImage;
PFNGLGETTEXPARAMETERFVPROC gl3wGetTexParameterfv;
PFNGLGETTEXPARAMETERIVPROC gl3wGetTexParameteriv;
PFNGLGETTEXLEVELPARAMETERFVPROC gl3wGetTexLevelParameterfv;
PFNGLGETTEXLEVELPARAMETERIVPROC gl3wGetTexLevelParameteriv;
PFNGLISENABLEDPROC gl3wIsEnabled;
PFNGLDEPTHRANGEPROC gl3wDepthRange;
PFNGLVIEWPORTPROC gl3wViewport;
PFNGLDRAWARRAYSPROC gl3wDrawArrays;
PFNGLDRAWELEMENTSPROC gl3wDrawElements;
PFNGLGETPOINTERVPROC gl3wGetPointerv;
PFNGLPOLYGONOFFSETPROC gl3wPolygonOffset;
PFNGLCOPYTEXIMAGE1DPROC gl3wCopyTexImage1D;
PFNGLCOPYTEXIMAGE2DPROC gl3wCopyTexImage2D;
PFNGLCOPYTEXSUBIMAGE1DPROC gl3wCopyTexSubImage1D;
PFNGLCOPYTEXSUBIMAGE2DPROC gl3wCopyTexSubImage2D;
PFNGLTEXSUBIMAGE1DPROC gl3wTexSubImage1D;
PFNGLTEXSUBIMAGE2DPROC gl3wTexSubImage2D;
PFNGLBINDTEXTUREPROC gl3wBindTexture;
PFNGLDELETETEXTURESPROC gl3wDeleteTextures;
PFNGLGENTEXTURESPROC gl3wGenTextures;
PFNGLISTEXTUREPROC gl3wIsTexture;
PFNGLBLENDCOLORPROC gl3wBlendColor;
PFNGLBLENDEQUATIONPROC gl3wBlendEquation;
PFNGLDRAWRANGEELEMENTSPROC gl3wDrawRangeElements;
PFNGLTEXIMAGE3DPROC gl3wTexImage3D;
PFNGLTEXSUBIMAGE3DPROC gl3wTexSubImage3D;
PFNGLCOPYTEXSUBIMAGE3DPROC gl3wCopyTexSubImage3D;
PFNGLACTIVETEXTUREPROC gl3wActiveTexture;
PFNGLSAMPLECOVERAGEPROC gl3wSampleCoverage;
PFNGLCOMPRESSEDTEXIMAGE3DPROC gl3wCompressedTexImage3D;
PFNGLCOMPRESSEDTEXIMAGE2DPROC gl3wCompressedTexImage2D;
PFNGLCOMPRESSEDTEXIMAGE1DPROC gl3wCompressedTexImage1D;
PFNGLCOMPRESSEDTEXSUBIMAGE3DPROC gl3wCompressedTexSubImage3D;
PFNGLCOMPRESSEDTEXSUBIMAGE2DPROC gl3wCompressedTexSubImage2D;
PFNGLCOMPRESSEDTEXSUBIMAGE1DPROC gl3wCompressedTexSubImage1D;
PFNGLGETCOMPRESSEDTEXIMAGEPROC gl3wGetCompressedTexImage;
PFNGLBLENDFUNCSEPARATEPROC gl3wBlendFuncSeparate;
PFNGLMULTIDRAWARRAYSPROC gl3wMultiDrawArrays;
PFNGLMULTIDRAWELEMENTSPROC gl3wMultiDrawElements;
PFNGLPOINTPARAMETERFPROC gl3wPointParameterf;
PFNGLPOINTPARAMETERFVPROC gl3wPointParameterfv;
PFNGLPOINTPARAMETERIPROC gl3wPointParameteri;
PFNGLPOINTPARAMETERIVPROC gl3wPointParameteriv;
PFNGLGENQUERIESPROC gl3wGenQueries;
PFNGLDELETEQUERIESPROC gl3wDeleteQueries;
PFNGLISQUERYPROC gl3wIsQuery;
PFNGLBEGINQUERYPROC gl3wBeginQuery;
PFNGLENDQUERYPROC gl3wEndQuery;
PFNGLGETQUERYIVPROC gl3wGetQueryiv;
PFNGLGETQUERYOBJECTIVPROC gl3wGetQueryObjectiv;
PFNGLGETQUERYOBJECTUIVPROC gl3wGetQueryObjectuiv;
PFNGLBINDBUFFERPROC gl3wBindBuffer;
PFNGLDELETEBUFFERSPROC gl3wDeleteBuffers;
PFNGLGENBUFFERSPROC gl3wGenBuffers;
PFNGLISBUFFERPROC gl3wIsBuffer;
PFNGLBUFFERDATAPROC gl3wBufferData;
PFNGLBUFFERSUBDATAPROC gl3wBufferSubData;
PFNGLGETBUFFERSUBDATAPROC gl3wGetBufferSubData;
PFNGLMAPBUFFERPROC gl3wMapBuffer;
PFNGLUNMAPBUFFERPROC gl3wUnmapBuffer;
PFNGLGETBUFFERPARAMETERIVPROC gl3wGetBufferParameteriv;
PFNGLGETBUFFERPOINTERVPROC gl3wGetBufferPointerv;
PFNGLBLENDEQUATIONSEPARATEPROC gl3wBlendEquationSeparate;
PFNGLDRAWBUFFERSPROC gl3wDrawBuffers;
PFNGLSTENCILOPSEPARATEPROC gl3wStencilOpSeparate;
PFNGLSTENCILFUNCSEPARATEPROC gl3wStencilFuncSeparate;
PFNGLSTENCILMASKSEPARATEPROC gl3wStencilMaskSeparate;
PFNGLATTACHSHADERPROC gl3wAttachShader;
PFNGLBINDATTRIBLOCATIONPROC gl3wBindAttribLocation;
PFNGLCOMPILESHADERPROC gl3wCompileShader;
PFNGLCREATEPROGRAMPROC gl3wCreateProgram;
PFNGLCREATESHADERPROC gl3wCreateShader;
PFNGLDELETEPROGRAMPROC gl3wDeleteProgram;
PFNGLDELETESHADERPROC gl3wDeleteShader;
PFNGLDETACHSHADERPROC gl3wDetachShader;
PFNGLDISABLEVERTEXATTRIBARRAYPROC gl3wDisableVertexAttribArray;
PFNGLENABLEVERTEXATTRIBARRAYPROC gl3wEnableVertexAttribArray;
PFNGLGETACTIVEATTRIBPROC gl3wGetActiveAttrib;
PFNGLGETACTIVEUNIFORMPROC gl3wGetActiveUniform;
PFNGLGETATTACHEDSHADERSPROC gl3wGetAttachedShaders;
PFNGLGETATTRIBLOCATIONPROC gl3wGetAttribLocation;
PFNGLGETPROGRAMIVPROC gl3wGetProgramiv;
PFNGLGETPROGRAMINFOLOGPROC gl3wGetProgramInfoLog;
PFNGLGETSHADERIVPROC gl3wGetShaderiv;
PFNGLGETSHADERINFOLOGPROC gl3wGetShaderInfoLog;
PFNGLGETSHADERSOURCEPROC gl3wGetShaderSource;
PFNGLGETUNIFORMLOCATIONPROC gl3wGetUniformLocation;
PFNGLGETUNIFORMFVPROC gl3wGetUniformfv;
PFNGLGETUNIFORMIVPROC gl3wGetUniformiv;
PFNGLGETVERTEXATTRIBDVPROC gl3wGetVertexAttribdv;
PFNGLGETVERTEXATTRIBFVPROC gl3wGetVertexAttribfv;
PFNGLGETVERTEXATTRIBIVPROC gl3wGetVertexAttribiv;
PFNGLGETVERTEXATTRIBPOINTERVPROC gl3wGetVertexAttribPointerv;
PFNGLISPROGRAMPROC gl3wIsProgram;
PFNGLISSHADERPROC gl3wIsShader;
PFNGLLINKPROGRAMPROC gl3wLinkProgram;
PFNGLSHADERSOURCEPROC gl3wShaderSource;
PFNGLUSEPROGRAMPROC gl3wUseProgram;
PFNGLUNIFORM1FPROC gl3wUniform1f;
PFNGLUNIFORM2FPROC gl3wUniform2f;
PFNGLUNIFORM3FPROC gl3wUniform3f;
PFNGLUNIFORM4FPROC gl3wUniform4f;
PFNGLUNIFORM1IPROC gl3wUniform1i;
PFNGLUNIFORM2IPROC gl3wUniform2i;
PFNGLUNIFORM3IPROC gl3wUniform3i;
PFNGLUNIFORM4IPROC gl3wUniform4i;
PFNGLUNIFORM1FVPROC gl3wUniform1fv;
PFNGLUNIFORM2FVPROC gl3wUniform2fv;
PFNGLUNIFORM3FVPROC gl3wUniform3fv;
PFNGLUNIFORM4FVPROC gl3wUniform4fv;
PFNGLUNIFORM1IVPROC gl3wUniform1iv;
PFNGLUNIFORM2IVPROC gl3wUniform2iv;
PFNGLUNIFORM3IVPROC gl3wUniform3iv;
PFNGLUNIFORM4IVPROC gl3wUniform4iv;
PFNGLUNIFORMMATRIX2FVPROC gl3wUniformMatrix2fv;
PFNGLUNIFORMMATRIX3FVPROC gl3wUniformMatrix3fv;
PFNGLUNIFORMMATRIX4FVPROC gl3wUniformMatrix4fv;
PFNGLVALIDATEPROGRAMPROC gl3wValidateProgram;
PFNGLVERTEXATTRIB1DPROC gl3wVertexAttrib1d;
PFNGLVERTEXATTRIB1DVPROC gl3wVertexAttrib1dv;
PFNGLVERTEXATTRIB1FPROC gl3wVertexAttrib1f;
PFNGLVERTEXATTRIB1FVPROC gl3wVertexAttrib1fv;
PFNGLVERTEXATTRIB1SPROC gl3wVertexAttrib1s;
PFNGLVERTEXATTRIB1SVPROC gl3wVertexAttrib1sv;
PFNGLVERTEXATTRIB2DPROC gl3wVertexAttrib2d;
PFNGLVERTEXATTRIB2DVPROC gl3wVertexAttrib2dv;
PFNGLVERTEXATTRIB2FPROC gl3wVertexAttrib2f;
PFNGLVERTEXATTRIB2FVPROC gl3wVertexAttrib2fv;
PFNGLVERTEXATTRIB2SPROC gl3wVertexAttrib2s;
PFNGLVERTEXATTRIB2SVPROC gl3wVertexAttrib2sv;
PFNGLVERTEXATTRIB3DPROC gl3wVertexAttrib3d;
PFNGLVERTEXATTRIB3DVPROC gl3wVertexAttrib3dv;
PFNGLVERTEXATTRIB3FPROC gl3wVertexAttrib3f;
PFNGLVERTEXATTRIB3FVPROC gl3wVertexAttrib3fv;
PFNGLVERTEXATTRIB3SPROC gl3wVertexAttrib3s;
PFNGLVERTEXATTRIB3SVPROC gl3wVertexAttrib3sv;
PFNGLVERTEXATTRIB4NBVPROC gl3wVertexAttrib4Nbv;
PFNGLVERTEXATTRIB4NIVPROC gl3wVertexAttrib4Niv;
PFNGLVERTEXATTRIB4NSVPROC gl3wVertexAttrib4Nsv;
PFNGLVERTEXATTRIB4NUBPROC gl3wVertexAttrib4Nub;
PFNGLVERTEXATTRIB4NUBVPROC gl3wVertexAttrib4Nubv;
PFNGLVERTEXATTRIB4NUIVPROC gl3wVertexAttrib4Nuiv;
PFNGLVERTEXATTRIB4NUSVPROC gl3wVertexAttrib4Nusv;
PFNGLVERTEXATTRIB4BVPROC gl3wVertexAttrib4bv;
PFNGLVERTEXATTRIB4DPROC gl3wVertexAttrib4d;
PFNGLVERTEXATTRIB4DVPROC gl3wVertexAttrib4dv;
PFNGLVERTEXATTRIB4FPROC gl3wVertexAttrib4f;
PFNGLVERTEXATTRIB4FVPROC gl3wVertexAttrib4fv;
PFNGLVERTEXATTRIB4IVPROC gl3wVertexAttrib4iv;
PFNGLVERTEXATTRIB4SPROC gl3wVertexAttrib4s;
PFNGLVERTEXATTRIB4SVPROC gl3wVertexAttrib4sv;
PFNGLVERTEXATTRIB4UBVPROC gl3wVertexAttrib4ubv;
PFNGLVERTEXATTRIB4UIVPROC gl3wVertexAttrib4uiv;
PFNGLVERTEXATTRIB4USVPROC gl3wVertexAttrib4usv;
PFNGLVERTEXATTRIBPOINTERPROC gl3wVertexAttribPointer;
PFNGLUNIFORMMATRIX2X3FVPROC gl3wUniformMatrix2x3fv;
PFNGLUNIFORMMATRIX3X2FVPROC gl3wUniformMatrix3x2fv;
PFNGLUNIFORMMATRIX2X4FVPROC gl3wUniformMatrix2x4fv;
PFNGLUNIFORMMATRIX4X2FVPROC gl3wUniformMatrix4x2fv;
PFNGLUNIFORMMATRIX3X4FVPROC gl3wUniformMatrix3x4fv;
PFNGLUNIFORMMATRIX4X3FVPROC gl3wUniformMatrix4x3fv;
PFNGLCOLORMASKIPROC gl3wColorMaski;
PFNGLGETBOOLEANI_VPROC gl3wGetBooleani_v;
PFNGLGETINTEGERI_VPROC gl3wGetIntegeri_v;
PFNGLENABLEIPROC gl3wEnablei;
PFNGLDISABLEIPROC gl3wDisablei;
PFNGLISENABLEDIPROC gl3wIsEnabledi;
PFNGLBEGINTRANSFORMFEEDBACKPROC gl3wBeginTransformFeedback;
PFNGLENDTRANSFORMFEEDBACKPROC gl3wEndTransformFeedback;
PFNGLBINDBUFFERRANGEPROC gl3wBindBufferRange;
PFNGLBINDBUFFERBASEPROC gl3wBindBufferBase;
PFNGLTRANSFORMFEEDBACKVARYINGSPROC gl3wTransformFeedbackVaryings;
PFNGLGETTRANSFORMFEEDBACKVARYINGPROC gl3wGetTransformFeedbackVarying;
PFNGLCLAMPCOLORPROC gl3wClampColor;
PFNGLBEGINCONDITIONALRENDERPROC gl3wBeginConditionalRender;
PFNGLENDCONDITIONALRENDERPROC gl3wEndConditionalRender;
PFNGLVERTEXATTRIBIPOINTERPROC gl3wVertexAttribIPointer;
PFNGLGETVERTEXATTRIBIIVPROC gl3wGetVertexAttribIiv;
PFNGLGETVERTEXATTRIBIUIVPROC gl3wGetVertexAttribIuiv;
PFNGLVERTEXATTRIBI1IPROC gl3wVertexAttribI1i;
PFNGLVERTEXATTRIBI2IPROC gl3wVertexAttribI2i;
PFNGLVERTEXATTRIBI3IPROC gl3wVertexAttribI3i;
PFNGLVERTEXATTRIBI4IPROC gl3wVertexAttribI4i;
PFNGLVERTEXATTRIBI1UIPROC gl3wVertexAttribI1ui;
PFNGLVERTEXATTRIBI2UIPROC gl3wVertexAttribI2ui;
PFNGLVERTEXATTRIBI3UIPROC gl3wVertexAttribI3ui;
PFNGLVERTEXATTRIBI4UIPROC gl3wVertexAttribI4ui;
PFNGLVERTEXATTRIBI1IVPROC gl3wVertexAttribI1iv;
PFNGLVERTEXATTRIBI2IVPROC gl3wVertexAttribI2iv;
PFNGLVERTEXATTRIBI3IVPROC gl3wVertexAttribI3iv;
PFNGLVERTEXATTRIBI4IVPROC gl3wVertexAttribI4iv;
PFNGLVERTEXATTRIBI1UIVPROC gl3wVertexAttribI1uiv;
PFNGLVERTEXATTRIBI2UIVPROC gl3wVertexAttribI2uiv;
PFNGLVERTEXATTRIBI3UIVPROC gl3wVertexAttribI3uiv;
PFNGLVERTEXATTRIBI4UIVPROC gl3wVertexAttribI4uiv;
PFNGLVERTEXATTRIBI4BVPROC gl3wVertexAttribI4bv;
PFNGLVERTEXATTRIBI4SVPROC gl3wVertexAttribI4sv;
PFNGLVERTEXATTRIBI4UBVPROC gl3wVertexAttribI4ubv;
PFNGLVERTEXATTRIBI4USVPROC gl3wVertexAttribI4usv;
PFNGLGETUNIFORMUIVPROC gl3wGetUniformuiv;
PFNGLBINDFRAGDATALOCATIONPROC gl3wBindFragDataLocation;
PFNGLGETFRAGDATALOCATIONPROC gl3wGetFragDataLocation;
PFNGLUNIFORM1UIPROC gl3wUniform1ui;
PFNGLUNIFORM2UIPROC gl3wUniform2ui;
PFNGLUNIFORM3UIPROC gl3wUniform3ui;
PFNGLUNIFORM4UIPROC gl3wUniform4ui;
PFNGLUNIFORM1UIVPROC gl3wUniform1uiv;
PFNGLUNIFORM2UIVPROC gl3wUniform2uiv;
PFNGLUNIFORM3UIVPROC gl3wUniform3uiv;
PFNGLUNIFORM4UIVPROC gl3wUniform4uiv;
PFNGLTEXPARAMETERIIVPROC gl3wTexParameterIiv;
PFNGLTEXPARAMETERIUIVPROC gl3wTexParameterIuiv;
PFNGLGETTEXPARAMETERIIVPROC gl3wGetTexParameterIiv;
PFNGLGETTEXPARAMETERIUIVPROC gl3wGetTexParameterIuiv;
PFNGLCLEARBUFFERIVPROC gl3wClearBufferiv;
PFNGLCLEARBUFFERUIVPROC gl3wClearBufferuiv;
PFNGLCLEARBUFFERFVPROC gl3wClearBufferfv;
PFNGLCLEARBUFFERFIPROC gl3wClearBufferfi;
PFNGLGETSTRINGIPROC gl3wGetStringi;
PFNGLDRAWARRAYSINSTANCEDPROC gl3wDrawArraysInstanced;
PFNGLDRAWELEMENTSINSTANCEDPROC gl3wDrawElementsInstanced;
PFNGLTEXBUFFERPROC gl3wTexBuffer;
PFNGLPRIMITIVERESTARTINDEXPROC gl3wPrimitiveRestartIndex;
PFNGLGETINTEGER64I_VPROC gl3wGetInteger64i_v;
PFNGLGETBUFFERPARAMETERI64VPROC gl3wGetBufferParameteri64v;
PFNGLFRAMEBUFFERTEXTUREPROC gl3wFramebufferTexture;
PFNGLVERTEXATTRIBDIVISORPROC gl3wVertexAttribDivisor;
PFNGLMINSAMPLESHADINGPROC gl3wMinSampleShading;
PFNGLBLENDEQUATIONIPROC gl3wBlendEquationi;
PFNGLBLENDEQUATIONSEPARATEIPROC gl3wBlendEquationSeparatei;
PFNGLBLENDFUNCIPROC gl3wBlendFunci;
PFNGLBLENDFUNCSEPARATEIPROC gl3wBlendFuncSeparatei;
PFNGLISRENDERBUFFERPROC gl3wIsRenderbuffer;
PFNGLBINDRENDERBUFFERPROC gl3wBindRenderbuffer;
PFNGLDELETERENDERBUFFERSPROC gl3wDeleteRenderbuffers;
PFNGLGENRENDERBUFFERSPROC gl3wGenRenderbuffers;
PFNGLRENDERBUFFERSTORAGEPROC gl3wRenderbufferStorage;
PFNGLGETRENDERBUFFERPARAMETERIVPROC gl3wGetRenderbufferParameteriv;
PFNGLISFRAMEBUFFERPROC gl3wIsFramebuffer;
PFNGLBINDFRAMEBUFFERPROC gl3wBindFramebuffer;
PFNGLDELETEFRAMEBUFFERSPROC gl3wDeleteFramebuffers;
PFNGLGENFRAMEBUFFERSPROC gl3wGenFramebuffers;
PFNGLCHECKFRAMEBUFFERSTATUSPROC gl3wCheckFramebufferStatus;
PFNGLFRAMEBUFFERTEXTURE1DPROC gl3wFramebufferTexture1D;
PFNGLFRAMEBUFFERTEXTURE2DPROC gl3wFramebufferTexture2D;
PFNGLFRAMEBUFFERTEXTURE3DPROC gl3wFramebufferTexture3D;
PFNGLFRAMEBUFFERRENDERBUFFERPROC gl3wFramebufferRenderbuffer;
PFNGLGETFRAMEBUFFERATTACHMENTPARAMETERIVPROC gl3wGetFramebufferAttachmentParameteriv;
PFNGLGENERATEMIPMAPPROC gl3wGenerateMipmap;
PFNGLBLITFRAMEBUFFERPROC gl3wBlitFramebuffer;
PFNGLRENDERBUFFERSTORAGEMULTISAMPLEPROC gl3wRenderbufferStorageMultisample;
PFNGLFRAMEBUFFERTEXTURELAYERPROC gl3wFramebufferTextureLayer;
PFNGLMAPBUFFERRANGEPROC gl3wMapBufferRange;
PFNGLFLUSHMAPPEDBUFFERRANGEPROC gl3wFlushMappedBufferRange;
PFNGLBINDVERTEXARRAYPROC gl3wBindVertexArray;
PFNGLDELETEVERTEXARRAYSPROC gl3wDeleteVertexArrays;
PFNGLGENVERTEXARRAYSPROC gl3wGenVertexArrays;
PFNGLISVERTEXARRAYPROC gl3wIsVertexArray;
PFNGLGETUNIFORMINDICESPROC gl3wGetUniformIndices;
PFNGLGETACTIVEUNIFORMSIVPROC gl3wGetActiveUniformsiv;
PFNGLGETACTIVEUNIFORMNAMEPROC gl3wGetActiveUniformName;
PFNGLGETUNIFORMBLOCKINDEXPROC gl3wGetUniformBlockIndex;
PFNGLGETACTIVEUNIFORMBLOCKIVPROC gl3wGetActiveUniformBlockiv;
PFNGLGETACTIVEUNIFORMBLOCKNAMEPROC gl3wGetActiveUniformBlockName;
PFNGLUNIFORMBLOCKBINDINGPROC gl3wUniformBlockBinding;
PFNGLCOPYBUFFERSUBDATAPROC gl3wCopyBufferSubData;
PFNGLDRAWELEMENTSBASEVERTEXPROC gl3wDrawElementsBaseVertex;
PFNGLDRAWRANGEELEMENTSBASEVERTEXPROC gl3wDrawRangeElementsBaseVertex;
PFNGLDRAWELEMENTSINSTANCEDBASEVERTEXPROC gl3wDrawElementsInstancedBaseVertex;
PFNGLMULTIDRAWELEMENTSBASEVERTEXPROC gl3wMultiDrawElementsBaseVertex;
PFNGLPROVOKINGVERTEXPROC gl3wProvokingVertex;
PFNGLFENCESYNCPROC gl3wFenceSync;
PFNGLISSYNCPROC gl3wIsSync;
PFNGLDELETESYNCPROC gl3wDeleteSync;
PFNGLCLIENTWAITSYNCPROC gl3wClientWaitSync;
PFNGLWAITSYNCPROC gl3wWaitSync;
PFNGLGETINTEGER64VPROC gl3wGetInteger64v;
PFNGLGETSYNCIVPROC gl3wGetSynciv;
PFNGLTEXIMAGE2DMULTISAMPLEPROC gl3wTexImage2DMultisample;
PFNGLTEXIMAGE3DMULTISAMPLEPROC gl3wTexImage3DMultisample;
PFNGLGETMULTISAMPLEFVPROC gl3wGetMultisamplefv;
PFNGLSAMPLEMASKIPROC gl3wSampleMaski;
PFNGLBLENDEQUATIONIARBPROC gl3wBlendEquationiARB;
PFNGLBLENDEQUATIONSEPARATEIARBPROC gl3wBlendEquationSeparateiARB;
PFNGLBLENDFUNCIARBPROC gl3wBlendFunciARB;
PFNGLBLENDFUNCSEPARATEIARBPROC gl3wBlendFuncSeparateiARB;
PFNGLMINSAMPLESHADINGARBPROC gl3wMinSampleShadingARB;
PFNGLNAMEDSTRINGARBPROC gl3wNamedStringARB;
PFNGLDELETENAMEDSTRINGARBPROC gl3wDeleteNamedStringARB;
PFNGLCOMPILESHADERINCLUDEARBPROC gl3wCompileShaderIncludeARB;
PFNGLISNAMEDSTRINGARBPROC gl3wIsNamedStringARB;
PFNGLGETNAMEDSTRINGARBPROC gl3wGetNamedStringARB;
PFNGLGETNAMEDSTRINGIVARBPROC gl3wGetNamedStringivARB;
PFNGLBINDFRAGDATALOCATIONINDEXEDPROC gl3wBindFragDataLocationIndexed;
PFNGLGETFRAGDATAINDEXPROC gl3wGetFragDataIndex;
PFNGLGENSAMPLERSPROC gl3wGenSamplers;
PFNGLDELETESAMPLERSPROC gl3wDeleteSamplers;
PFNGLISSAMPLERPROC gl3wIsSampler;
PFNGLBINDSAMPLERPROC gl3wBindSampler;
PFNGLSAMPLERPARAMETERIPROC gl3wSamplerParameteri;
PFNGLSAMPLERPARAMETERIVPROC gl3wSamplerParameteriv;
PFNGLSAMPLERPARAMETERFPROC gl3wSamplerParameterf;
PFNGLSAMPLERPARAMETERFVPROC gl3wSamplerParameterfv;
PFNGLSAMPLERPARAMETERIIVPROC gl3wSamplerParameterIiv;
PFNGLSAMPLERPARAMETERIUIVPROC gl3wSamplerParameterIuiv;
PFNGLGETSAMPLERPARAMETERIVPROC gl3wGetSamplerParameteriv;
PFNGLGETSAMPLERPARAMETERIIVPROC gl3wGetSamplerParameterIiv;
PFNGLGETSAMPLERPARAMETERFVPROC gl3wGetSamplerParameterfv;
PFNGLGETSAMPLERPARAMETERIUIVPROC gl3wGetSamplerParameterIuiv;
PFNGLQUERYCOUNTERPROC gl3wQueryCounter;
PFNGLGETQUERYOBJECTI64VPROC gl3wGetQueryObjecti64v;
PFNGLGETQUERYOBJECTUI64VPROC gl3wGetQueryObjectui64v;
PFNGLVERTEXP2UIPROC gl3wVertexP2ui;
PFNGLVERTEXP2UIVPROC gl3wVertexP2uiv;
PFNGLVERTEXP3UIPROC gl3wVertexP3ui;
PFNGLVERTEXP3UIVPROC gl3wVertexP3uiv;
PFNGLVERTEXP4UIPROC gl3wVertexP4ui;
PFNGLVERTEXP4UIVPROC gl3wVertexP4uiv;
PFNGLTEXCOORDP1UIPROC gl3wTexCoordP1ui;
PFNGLTEXCOORDP1UIVPROC gl3wTexCoordP1uiv;
PFNGLTEXCOORDP2UIPROC gl3wTexCoordP2ui;
PFNGLTEXCOORDP2UIVPROC gl3wTexCoordP2uiv;
PFNGLTEXCOORDP3UIPROC gl3wTexCoordP3ui;
PFNGLTEXCOORDP3UIVPROC gl3wTexCoordP3uiv;
PFNGLTEXCOORDP4UIPROC gl3wTexCoordP4ui;
PFNGLTEXCOORDP4UIVPROC gl3wTexCoordP4uiv;
PFNGLMULTITEXCOORDP1UIPROC gl3wMultiTexCoordP1ui;
PFNGLMULTITEXCOORDP1UIVPROC gl3wMultiTexCoordP1uiv;
PFNGLMULTITEXCOORDP2UIPROC gl3wMultiTexCoordP2ui;
PFNGLMULTITEXCOORDP2UIVPROC gl3wMultiTexCoordP2uiv;
PFNGLMULTITEXCOORDP3UIPROC gl3wMultiTexCoordP3ui;
PFNGLMULTITEXCOORDP3UIVPROC gl3wMultiTexCoordP3uiv;
PFNGLMULTITEXCOORDP4UIPROC gl3wMultiTexCoordP4ui;
PFNGLMULTITEXCOORDP4UIVPROC gl3wMultiTexCoordP4uiv;
PFNGLNORMALP3UIPROC gl3wNormalP3ui;
PFNGLNORMALP3UIVPROC gl3wNormalP3uiv;
PFNGLCOLORP3UIPROC gl3wColorP3ui;
PFNGLCOLORP3UIVPROC gl3wColorP3uiv;
PFNGLCOLORP4UIPROC gl3wColorP4ui;
PFNGLCOLORP4UIVPROC gl3wColorP4uiv;
PFNGLSECONDARYCOLORP3UIPROC gl3wSecondaryColorP3ui;
PFNGLSECONDARYCOLORP3UIVPROC gl3wSecondaryColorP3uiv;
PFNGLVERTEXATTRIBP1UIPROC gl3wVertexAttribP1ui;
PFNGLVERTEXATTRIBP1UIVPROC gl3wVertexAttribP1uiv;
PFNGLVERTEXATTRIBP2UIPROC gl3wVertexAttribP2ui;
PFNGLVERTEXATTRIBP2UIVPROC gl3wVertexAttribP2uiv;
PFNGLVERTEXATTRIBP3UIPROC gl3wVertexAttribP3ui;
PFNGLVERTEXATTRIBP3UIVPROC gl3wVertexAttribP3uiv;
PFNGLVERTEXATTRIBP4UIPROC gl3wVertexAttribP4ui;
PFNGLVERTEXATTRIBP4UIVPROC gl3wVertexAttribP4uiv;
PFNGLDRAWARRAYSINDIRECTPROC gl3wDrawArraysIndirect;
PFNGLDRAWELEMENTSINDIRECTPROC gl3wDrawElementsIndirect;
PFNGLUNIFORM1DPROC gl3wUniform1d;
PFNGLUNIFORM2DPROC gl3wUniform2d;
PFNGLUNIFORM3DPROC gl3wUniform3d;
PFNGLUNIFORM4DPROC gl3wUniform4d;
PFNGLUNIFORM1DVPROC gl3wUniform1dv;
PFNGLUNIFORM2DVPROC gl3wUniform2dv;
PFNGLUNIFORM3DVPROC gl3wUniform3dv;
PFNGLUNIFORM4DVPROC gl3wUniform4dv;
PFNGLUNIFORMMATRIX2DVPROC gl3wUniformMatrix2dv;
PFNGLUNIFORMMATRIX3DVPROC gl3wUniformMatrix3dv;
PFNGLUNIFORMMATRIX4DVPROC gl3wUniformMatrix4dv;
PFNGLUNIFORMMATRIX2X3DVPROC gl3wUniformMatrix2x3dv;
PFNGLUNIFORMMATRIX2X4DVPROC gl3wUniformMatrix2x4dv;
PFNGLUNIFORMMATRIX3X2DVPROC gl3wUniformMatrix3x2dv;
PFNGLUNIFORMMATRIX3X4DVPROC gl3wUniformMatrix3x4dv;
PFNGLUNIFORMMATRIX4X2DVPROC gl3wUniformMatrix4x2dv;
PFNGLUNIFORMMATRIX4X3DVPROC gl3wUniformMatrix4x3dv;
PFNGLGETUNIFORMDVPROC gl3wGetUniformdv;
PFNGLGETSUBROUTINEUNIFORMLOCATIONPROC gl3wGetSubroutineUniformLocation;
PFNGLGETSUBROUTINEINDEXPROC gl3wGetSubroutineIndex;
PFNGLGETACTIVESUBROUTINEUNIFORMIVPROC gl3wGetActiveSubroutineUniformiv;
PFNGLGETACTIVESUBROUTINEUNIFORMNAMEPROC gl3wGetActiveSubroutineUniformName;
PFNGLGETACTIVESUBROUTINENAMEPROC gl3wGetActiveSubroutineName;
PFNGLUNIFORMSUBROUTINESUIVPROC gl3wUniformSubroutinesuiv;
PFNGLGETUNIFORMSUBROUTINEUIVPROC gl3wGetUniformSubroutineuiv;
PFNGLGETPROGRAMSTAGEIVPROC gl3wGetProgramStageiv;
PFNGLPATCHPARAMETERIPROC gl3wPatchParameteri;
PFNGLPATCHPARAMETERFVPROC gl3wPatchParameterfv;
PFNGLBINDTRANSFORMFEEDBACKPROC gl3wBindTransformFeedback;
PFNGLDELETETRANSFORMFEEDBACKSPROC gl3wDeleteTransformFeedbacks;
PFNGLGENTRANSFORMFEEDBACKSPROC gl3wGenTransformFeedbacks;
PFNGLISTRANSFORMFEEDBACKPROC gl3wIsTransformFeedback;
PFNGLPAUSETRANSFORMFEEDBACKPROC gl3wPauseTransformFeedback;
PFNGLRESUMETRANSFORMFEEDBACKPROC gl3wResumeTransformFeedback;
PFNGLDRAWTRANSFORMFEEDBACKPROC gl3wDrawTransformFeedback;
PFNGLDRAWTRANSFORMFEEDBACKSTREAMPROC gl3wDrawTransformFeedbackStream;
PFNGLBEGINQUERYINDEXEDPROC gl3wBeginQueryIndexed;
PFNGLENDQUERYINDEXEDPROC gl3wEndQueryIndexed;
PFNGLGETQUERYINDEXEDIVPROC gl3wGetQueryIndexediv;
PFNGLRELEASESHADERCOMPILERPROC gl3wReleaseShaderCompiler;
PFNGLSHADERBINARYPROC gl3wShaderBinary;
PFNGLGETSHADERPRECISIONFORMATPROC gl3wGetShaderPrecisionFormat;
PFNGLDEPTHRANGEFPROC gl3wDepthRangef;
PFNGLCLEARDEPTHFPROC gl3wClearDepthf;
PFNGLGETPROGRAMBINARYPROC gl3wGetProgramBinary;
PFNGLPROGRAMBINARYPROC gl3wProgramBinary;
PFNGLPROGRAMPARAMETERIPROC gl3wProgramParameteri;
PFNGLUSEPROGRAMSTAGESPROC gl3wUseProgramStages;
PFNGLACTIVESHADERPROGRAMPROC gl3wActiveShaderProgram;
PFNGLCREATESHADERPROGRAMVPROC gl3wCreateShaderProgramv;
PFNGLBINDPROGRAMPIPELINEPROC gl3wBindProgramPipeline;
PFNGLDELETEPROGRAMPIPELINESPROC gl3wDeleteProgramPipelines;
PFNGLGENPROGRAMPIPELINESPROC gl3wGenProgramPipelines;
PFNGLISPROGRAMPIPELINEPROC gl3wIsProgramPipeline;
PFNGLGETPROGRAMPIPELINEIVPROC gl3wGetProgramPipelineiv;
PFNGLPROGRAMUNIFORM1IPROC gl3wProgramUniform1i;
PFNGLPROGRAMUNIFORM1IVPROC gl3wProgramUniform1iv;
PFNGLPROGRAMUNIFORM1FPROC gl3wProgramUniform1f;
PFNGLPROGRAMUNIFORM1FVPROC gl3wProgramUniform1fv;
PFNGLPROGRAMUNIFORM1DPROC gl3wProgramUniform1d;
PFNGLPROGRAMUNIFORM1DVPROC gl3wProgramUniform1dv;
PFNGLPROGRAMUNIFORM1UIPROC gl3wProgramUniform1ui;
PFNGLPROGRAMUNIFORM1UIVPROC gl3wProgramUniform1uiv;
PFNGLPROGRAMUNIFORM2IPROC gl3wProgramUniform2i;
PFNGLPROGRAMUNIFORM2IVPROC gl3wProgramUniform2iv;
PFNGLPROGRAMUNIFORM2FPROC gl3wProgramUniform2f;
PFNGLPROGRAMUNIFORM2FVPROC gl3wProgramUniform2fv;
PFNGLPROGRAMUNIFORM2DPROC gl3wProgramUniform2d;
PFNGLPROGRAMUNIFORM2DVPROC gl3wProgramUniform2dv;
PFNGLPROGRAMUNIFORM2UIPROC gl3wProgramUniform2ui;
PFNGLPROGRAMUNIFORM2UIVPROC gl3wProgramUniform2uiv;
PFNGLPROGRAMUNIFORM3IPROC gl3wProgramUniform3i;
PFNGLPROGRAMUNIFORM3IVPROC gl3wProgramUniform3iv;
PFNGLPROGRAMUNIFORM3FPROC gl3wProgramUniform3f;
PFNGLPROGRAMUNIFORM3FVPROC gl3wProgramUniform3fv;
PFNGLPROGRAMUNIFORM3DPROC gl3wProgramUniform3d;
PFNGLPROGRAMUNIFORM3DVPROC gl3wProgramUniform3dv;
PFNGLPROGRAMUNIFORM3UIPROC gl3wProgramUniform3ui;
PFNGLPROGRAMUNIFORM3UIVPROC gl3wProgramUniform3uiv;
PFNGLPROGRAMUNIFORM4IPROC gl3wProgramUniform4i;
PFNGLPROGRAMUNIFORM4IVPROC gl3wProgramUniform4iv;
PFNGLPROGRAMUNIFORM4FPROC gl3wProgramUniform4f;
PFNGLPROGRAMUNIFORM4FVPROC gl3wProgramUniform4fv;
PFNGLPROGRAMUNIFORM4DPROC gl3wProgramUniform4d;
PFNGLPROGRAMUNIFORM4DVPROC gl3wProgramUniform4dv;
PFNGLPROGRAMUNIFORM4UIPROC gl3wProgramUniform4ui;
PFNGLPROGRAMUNIFORM4UIVPROC gl3wProgramUniform4uiv;
PFNGLPROGRAMUNIFORMMATRIX2FVPROC gl3wProgramUniformMatrix2fv;
PFNGLPROGRAMUNIFORMMATRIX3FVPROC gl3wProgramUniformMatrix3fv;
PFNGLPROGRAMUNIFORMMATRIX4FVPROC gl3wProgramUniformMatrix4fv;
PFNGLPROGRAMUNIFORMMATRIX2DVPROC gl3wProgramUniformMatrix2dv;
PFNGLPROGRAMUNIFORMMATRIX3DVPROC gl3wProgramUniformMatrix3dv;
PFNGLPROGRAMUNIFORMMATRIX4DVPROC gl3wProgramUniformMatrix4dv;
PFNGLPROGRAMUNIFORMMATRIX2X3FVPROC gl3wProgramUniformMatrix2x3fv;
PFNGLPROGRAMUNIFORMMATRIX3X2FVPROC gl3wProgramUniformMatrix3x2fv;
PFNGLPROGRAMUNIFORMMATRIX2X4FVPROC gl3wProgramUniformMatrix2x4fv;
PFNGLPROGRAMUNIFORMMATRIX4X2FVPROC gl3wProgramUniformMatrix4x2fv;
PFNGLPROGRAMUNIFORMMATRIX3X4FVPROC gl3wProgramUniformMatrix3x4fv;
PFNGLPROGRAMUNIFORMMATRIX4X3FVPROC gl3wProgramUniformMatrix4x3fv;
PFNGLPROGRAMUNIFORMMATRIX2X3DVPROC gl3wProgramUniformMatrix2x3dv;
PFNGLPROGRAMUNIFORMMATRIX3X2DVPROC gl3wProgramUniformMatrix3x2dv;
PFNGLPROGRAMUNIFORMMATRIX2X4DVPROC gl3wProgramUniformMatrix2x4dv;
PFNGLPROGRAMUNIFORMMATRIX4X2DVPROC gl3wProgramUniformMatrix4x2dv;
PFNGLPROGRAMUNIFORMMATRIX3X4DVPROC gl3wProgramUniformMatrix3x4dv;
PFNGLPROGRAMUNIFORMMATRIX4X3DVPROC gl3wProgramUniformMatrix4x3dv;
PFNGLVALIDATEPROGRAMPIPELINEPROC gl3wValidateProgramPipeline;
PFNGLGETPROGRAMPIPELINEINFOLOGPROC gl3wGetProgramPipelineInfoLog;
PFNGLVERTEXATTRIBL1DPROC gl3wVertexAttribL1d;
PFNGLVERTEXATTRIBL2DPROC gl3wVertexAttribL2d;
PFNGLVERTEXATTRIBL3DPROC gl3wVertexAttribL3d;
PFNGLVERTEXATTRIBL4DPROC gl3wVertexAttribL4d;
PFNGLVERTEXATTRIBL1DVPROC gl3wVertexAttribL1dv;
PFNGLVERTEXATTRIBL2DVPROC gl3wVertexAttribL2dv;
PFNGLVERTEXATTRIBL3DVPROC gl3wVertexAttribL3dv;
PFNGLVERTEXATTRIBL4DVPROC gl3wVertexAttribL4dv;
PFNGLVERTEXATTRIBLPOINTERPROC gl3wVertexAttribLPointer;
PFNGLGETVERTEXATTRIBLDVPROC gl3wGetVertexAttribLdv;
PFNGLVIEWPORTARRAYVPROC gl3wViewportArrayv;
PFNGLVIEWPORTINDEXEDFPROC gl3wViewportIndexedf;
PFNGLVIEWPORTINDEXEDFVPROC gl3wViewportIndexedfv;
PFNGLSCISSORARRAYVPROC gl3wScissorArrayv;
PFNGLSCISSORINDEXEDPROC gl3wScissorIndexed;
PFNGLSCISSORINDEXEDVPROC gl3wScissorIndexedv;
PFNGLDEPTHRANGEARRAYVPROC gl3wDepthRangeArrayv;
PFNGLDEPTHRANGEINDEXEDPROC gl3wDepthRangeIndexed;
PFNGLGETFLOATI_VPROC gl3wGetFloati_v;
PFNGLGETDOUBLEI_VPROC gl3wGetDoublei_v;
PFNGLCREATESYNCFROMCLEVENTARBPROC gl3wCreateSyncFromCLeventARB;
PFNGLDEBUGMESSAGECONTROLARBPROC gl3wDebugMessageControlARB;
PFNGLDEBUGMESSAGEINSERTARBPROC gl3wDebugMessageInsertARB;
PFNGLDEBUGMESSAGECALLBACKARBPROC gl3wDebugMessageCallbackARB;
PFNGLGETDEBUGMESSAGELOGARBPROC gl3wGetDebugMessageLogARB;
PFNGLGETGRAPHICSRESETSTATUSARBPROC gl3wGetGraphicsResetStatusARB;
PFNGLGETNTEXIMAGEARBPROC gl3wGetnTexImageARB;
PFNGLREADNPIXELSARBPROC gl3wReadnPixelsARB;
PFNGLGETNCOMPRESSEDTEXIMAGEARBPROC gl3wGetnCompressedTexImageARB;
PFNGLGETNUNIFORMFVARBPROC gl3wGetnUniformfvARB;
PFNGLGETNUNIFORMIVARBPROC gl3wGetnUniformivARB;
PFNGLGETNUNIFORMUIVARBPROC gl3wGetnUniformuivARB;
PFNGLGETNUNIFORMDVARBPROC gl3wGetnUniformdvARB;
PFNGLDRAWARRAYSINSTANCEDBASEINSTANCEPROC gl3wDrawArraysInstancedBaseInstance;
PFNGLDRAWELEMENTSINSTANCEDBASEINSTANCEPROC gl3wDrawElementsInstancedBaseInstance;
PFNGLDRAWELEMENTSINSTANCEDBASEVERTEXBASEINSTANCEPROC gl3wDrawElementsInstancedBaseVertexBaseInstance;
PFNGLDRAWTRANSFORMFEEDBACKINSTANCEDPROC gl3wDrawTransformFeedbackInstanced;
PFNGLDRAWTRANSFORMFEEDBACKSTREAMINSTANCEDPROC gl3wDrawTransformFeedbackStreamInstanced;
PFNGLGETINTERNALFORMATIVPROC gl3wGetInternalformativ;
PFNGLGETACTIVEATOMICCOUNTERBUFFERIVPROC gl3wGetActiveAtomicCounterBufferiv;
PFNGLBINDIMAGETEXTUREPROC gl3wBindImageTexture;
PFNGLMEMORYBARRIERPROC gl3wMemoryBarrier;
PFNGLTEXSTORAGE1DPROC gl3wTexStorage1D;
PFNGLTEXSTORAGE2DPROC gl3wTexStorage2D;
PFNGLTEXSTORAGE3DPROC gl3wTexStorage3D;
PFNGLTEXTURESTORAGE1DEXTPROC gl3wTextureStorage1DEXT;
PFNGLTEXTURESTORAGE2DEXTPROC gl3wTextureStorage2DEXT;
PFNGLTEXTURESTORAGE3DEXTPROC gl3wTextureStorage3DEXT;
PFNGLDEBUGMESSAGECONTROLPROC gl3wDebugMessageControl;
PFNGLDEBUGMESSAGEINSERTPROC gl3wDebugMessageInsert;
PFNGLDEBUGMESSAGECALLBACKPROC gl3wDebugMessageCallback;
PFNGLGETDEBUGMESSAGELOGPROC gl3wGetDebugMessageLog;
PFNGLPUSHDEBUGGROUPPROC gl3wPushDebugGroup;
PFNGLPOPDEBUGGROUPPROC gl3wPopDebugGroup;
PFNGLOBJECTLABELPROC gl3wObjectLabel;
PFNGLGETOBJECTLABELPROC gl3wGetObjectLabel;
PFNGLOBJECTPTRLABELPROC gl3wObjectPtrLabel;
PFNGLGETOBJECTPTRLABELPROC gl3wGetObjectPtrLabel;
PFNGLCLEARBUFFERDATAPROC gl3wClearBufferData;
PFNGLCLEARBUFFERSUBDATAPROC gl3wClearBufferSubData;
PFNGLCLEARNAMEDBUFFERDATAEXTPROC gl3wClearNamedBufferDataEXT;
PFNGLCLEARNAMEDBUFFERSUBDATAEXTPROC gl3wClearNamedBufferSubDataEXT;
PFNGLDISPATCHCOMPUTEPROC gl3wDispatchCompute;
PFNGLDISPATCHCOMPUTEINDIRECTPROC gl3wDispatchComputeIndirect;
PFNGLCOPYIMAGESUBDATAPROC gl3wCopyImageSubData;
PFNGLTEXTUREVIEWPROC gl3wTextureView;
PFNGLBINDVERTEXBUFFERPROC gl3wBindVertexBuffer;
PFNGLVERTEXATTRIBFORMATPROC gl3wVertexAttribFormat;
PFNGLVERTEXATTRIBIFORMATPROC gl3wVertexAttribIFormat;
PFNGLVERTEXATTRIBLFORMATPROC gl3wVertexAttribLFormat;
PFNGLVERTEXATTRIBBINDINGPROC gl3wVertexAttribBinding;
PFNGLVERTEXBINDINGDIVISORPROC gl3wVertexBindingDivisor;
PFNGLVERTEXARRAYBINDVERTEXBUFFEREXTPROC gl3wVertexArrayBindVertexBufferEXT;
PFNGLVERTEXARRAYVERTEXATTRIBFORMATEXTPROC gl3wVertexArrayVertexAttribFormatEXT;
PFNGLVERTEXARRAYVERTEXATTRIBIFORMATEXTPROC gl3wVertexArrayVertexAttribIFormatEXT;
PFNGLVERTEXARRAYVERTEXATTRIBLFORMATEXTPROC gl3wVertexArrayVertexAttribLFormatEXT;
PFNGLVERTEXARRAYVERTEXATTRIBBINDINGEXTPROC gl3wVertexArrayVertexAttribBindingEXT;
PFNGLVERTEXARRAYVERTEXBINDINGDIVISOREXTPROC gl3wVertexArrayVertexBindingDivisorEXT;
PFNGLFRAMEBUFFERPARAMETERIPROC gl3wFramebufferParameteri;
PFNGLGETFRAMEBUFFERPARAMETERIVPROC gl3wGetFramebufferParameteriv;
PFNGLNAMEDFRAMEBUFFERPARAMETERIEXTPROC gl3wNamedFramebufferParameteriEXT;
PFNGLGETNAMEDFRAMEBUFFERPARAMETERIVEXTPROC gl3wGetNamedFramebufferParameterivEXT;
PFNGLGETINTERNALFORMATI64VPROC gl3wGetInternalformati64v;
PFNGLINVALIDATETEXSUBIMAGEPROC gl3wInvalidateTexSubImage;
PFNGLINVALIDATETEXIMAGEPROC gl3wInvalidateTexImage;
PFNGLINVALIDATEBUFFERSUBDATAPROC gl3wInvalidateBufferSubData;
PFNGLINVALIDATEBUFFERDATAPROC gl3wInvalidateBufferData;
PFNGLINVALIDATEFRAMEBUFFERPROC gl3wInvalidateFramebuffer;
PFNGLINVALIDATESUBFRAMEBUFFERPROC gl3wInvalidateSubFramebuffer;
PFNGLMULTIDRAWARRAYSINDIRECTPROC gl3wMultiDrawArraysIndirect;
PFNGLMULTIDRAWELEMENTSINDIRECTPROC gl3wMultiDrawElementsIndirect;
PFNGLGETPROGRAMINTERFACEIVPROC gl3wGetProgramInterfaceiv;
PFNGLGETPROGRAMRESOURCEINDEXPROC gl3wGetProgramResourceIndex;
PFNGLGETPROGRAMRESOURCENAMEPROC gl3wGetProgramResourceName;
PFNGLGETPROGRAMRESOURCEIVPROC gl3wGetProgramResourceiv;
PFNGLGETPROGRAMRESOURCELOCATIONPROC gl3wGetProgramResourceLocation;
PFNGLGETPROGRAMRESOURCELOCATIONINDEXPROC gl3wGetProgramResourceLocationIndex;
PFNGLSHADERSTORAGEBLOCKBINDINGPROC gl3wShaderStorageBlockBinding;
PFNGLTEXBUFFERRANGEPROC gl3wTexBufferRange;
PFNGLTEXTUREBUFFERRANGEEXTPROC gl3wTextureBufferRangeEXT;
PFNGLTEXSTORAGE2DMULTISAMPLEPROC gl3wTexStorage2DMultisample;
PFNGLTEXSTORAGE3DMULTISAMPLEPROC gl3wTexStorage3DMultisample;
PFNGLTEXTURESTORAGE2DMULTISAMPLEEXTPROC gl3wTextureStorage2DMultisampleEXT;
PFNGLTEXTURESTORAGE3DMULTISAMPLEEXTPROC gl3wTextureStorage3DMultisampleEXT;

static void load_procs(void)
{
    gl3wCullFace = (PFNGLCULLFACEPROC) get_proc("glCullFace");
    gl3wFrontFace = (PFNGLFRONTFACEPROC) get_proc("glFrontFace");
    gl3wHint = (PFNGLHINTPROC) get_proc("glHint");
    gl3wLineWidth = (PFNGLLINEWIDTHPROC) get_proc("glLineWidth");
    gl3wPointSize = (PFNGLPOINTSIZEPROC) get_proc("glPointSize");
    gl3wPolygonMode = (PFNGLPOLYGONMODEPROC) get_proc("glPolygonMode");
    gl3wScissor = (PFNGLSCISSORPROC) get_proc("glScissor");
    gl3wTexParameterf = (PFNGLTEXPARAMETERFPROC) get_proc("glTexParameterf");
    gl3wTexParameterfv = (PFNGLTEXPARAMETERFVPROC) get_proc("glTexParameterfv");
    gl3wTexParameteri = (PFNGLTEXPARAMETERIPROC) get_proc("glTexParameteri");
    gl3wTexParameteriv = (PFNGLTEXPARAMETERIVPROC) get_proc("glTexParameteriv");
    gl3wTexImage1D = (PFNGLTEXIMAGE1DPROC) get_proc("glTexImage1D");
    gl3wTexImage2D = (PFNGLTEXIMAGE2DPROC) get_proc("glTexImage2D");
    gl3wDrawBuffer = (PFNGLDRAWBUFFERPROC) get_proc("glDrawBuffer");
    gl3wClear = (PFNGLCLEARPROC) get_proc("glClear");
    gl3wClearColor = (PFNGLCLEARCOLORPROC) get_proc("glClearColor");
    gl3wClearStencil = (PFNGLCLEARSTENCILPROC) get_proc("glClearStencil");
    gl3wClearDepth = (PFNGLCLEARDEPTHPROC) get_proc("glClearDepth");
    gl3wStencilMask = (PFNGLSTENCILMASKPROC) get_proc("glStencilMask");
    gl3wColorMask = (PFNGLCOLORMASKPROC) get_proc("glColorMask");
    gl3wDepthMask = (PFNGLDEPTHMASKPROC) get_proc("glDepthMask");
    gl3wDisable = (PFNGLDISABLEPROC) get_proc("glDisable");
    gl3wEnable = (PFNGLENABLEPROC) get_proc("glEnable");
    gl3wFinish = (PFNGLFINISHPROC) get_proc("glFinish");
    gl3wFlush = (PFNGLFLUSHPROC) get_proc("glFlush");
    gl3wBlendFunc = (PFNGLBLENDFUNCPROC) get_proc("glBlendFunc");
    gl3wLogicOp = (PFNGLLOGICOPPROC) get_proc("glLogicOp");
    gl3wStencilFunc = (PFNGLSTENCILFUNCPROC) get_proc("glStencilFunc");
    gl3wStencilOp = (PFNGLSTENCILOPPROC) get_proc("glStencilOp");
    gl3wDepthFunc = (PFNGLDEPTHFUNCPROC) get_proc("glDepthFunc");
    gl3wPixelStoref = (PFNGLPIXELSTOREFPROC) get_proc("glPixelStoref");
    gl3wPixelStorei = (PFNGLPIXELSTOREIPROC) get_proc("glPixelStorei");
    gl3wReadBuffer = (PFNGLREADBUFFERPROC) get_proc("glReadBuffer");
    gl3wReadPixels = (PFNGLREADPIXELSPROC) get_proc("glReadPixels");
    gl3wGetBooleanv = (PFNGLGETBOOLEANVPROC) get_proc("glGetBooleanv");
    gl3wGetDoublev = (PFNGLGETDOUBLEVPROC) get_proc("glGetDoublev");
    gl3wGetError = (PFNGLGETERRORPROC) get_proc("glGetError");
    gl3wGetFloatv = (PFNGLGETFLOATVPROC) get_proc("glGetFloatv");
    gl3wGetIntegerv = (PFNGLGETINTEGERVPROC) get_proc("glGetIntegerv");
    gl3wGetString = (PFNGLGETSTRINGPROC) get_proc("glGetString");
    gl3wGetTexImage = (PFNGLGETTEXIMAGEPROC) get_proc("glGetTexImage");
    gl3wGetTexParameterfv = (PFNGLGETTEXPARAMETERFVPROC) get_proc("glGetTexParameterfv");
    gl3wGetTexParameteriv = (PFNGLGETTEXPARAMETERIVPROC) get_proc("glGetTexParameteriv");
    gl3wGetTexLevelParameterfv = (PFNGLGETTEXLEVELPARAMETERFVPROC) get_proc("glGetTexLevelParameterfv");
    gl3wGetTexLevelParameteriv = (PFNGLGETTEXLEVELPARAMETERIVPROC) get_proc("glGetTexLevelParameteriv");
    gl3wIsEnabled = (PFNGLISENABLEDPROC) get_proc("glIsEnabled");
    gl3wDepthRange = (PFNGLDEPTHRANGEPROC) get_proc("glDepthRange");
    gl3wViewport = (PFNGLVIEWPORTPROC) get_proc("glViewport");
    gl3wDrawArrays = (PFNGLDRAWARRAYSPROC) get_proc("glDrawArrays");
    gl3wDrawElements = (PFNGLDRAWELEMENTSPROC) get_proc("glDrawElements");
    gl3wGetPointerv = (PFNGLGETPOINTERVPROC) get_proc("glGetPointerv");
    gl3wPolygonOffset = (PFNGLPOLYGONOFFSETPROC) get_proc("glPolygonOffset");
    gl3wCopyTexImage1D = (PFNGLCOPYTEXIMAGE1DPROC) get_proc("glCopyTexImage1D");
    gl3wCopyTexImage2D = (PFNGLCOPYTEXIMAGE2DPROC) get_proc("glCopyTexImage2D");
    gl3wCopyTexSubImage1D = (PFNGLCOPYTEXSUBIMAGE1DPROC) get_proc("glCopyTexSubImage1D");
    gl3wCopyTexSubImage2D = (PFNGLCOPYTEXSUBIMAGE2DPROC) get_proc("glCopyTexSubImage2D");
    gl3wTexSubImage1D = (PFNGLTEXSUBIMAGE1DPROC) get_proc("glTexSubImage1D");
    gl3wTexSubImage2D = (PFNGLTEXSUBIMAGE2DPROC) get_proc("glTexSubImage2D");
    gl3wBindTexture = (PFNGLBINDTEXTUREPROC) get_proc("glBindTexture");
    gl3wDeleteTextures = (PFNGLDELETETEXTURESPROC) get_proc("glDeleteTextures");
    gl3wGenTextures = (PFNGLGENTEXTURESPROC) get_proc("glGenTextures");
    gl3wIsTexture = (PFNGLISTEXTUREPROC) get_proc("glIsTexture");
    gl3wBlendColor = (PFNGLBLENDCOLORPROC) get_proc("glBlendColor");
    gl3wBlendEquation = (PFNGLBLENDEQUATIONPROC) get_proc("glBlendEquation");
    gl3wDrawRangeElements = (PFNGLDRAWRANGEELEMENTSPROC) get_proc("glDrawRangeElements");
    gl3wTexImage3D = (PFNGLTEXIMAGE3DPROC) get_proc("glTexImage3D");
    gl3wTexSubImage3D = (PFNGLTEXSUBIMAGE3DPROC) get_proc("glTexSubImage3D");
    gl3wCopyTexSubImage3D = (PFNGLCOPYTEXSUBIMAGE3DPROC) get_proc("glCopyTexSubImage3D");
    gl3wActiveTexture = (PFNGLACTIVETEXTUREPROC) get_proc("glActiveTexture");
    gl3wSampleCoverage = (PFNGLSAMPLECOVERAGEPROC) get_proc("glSampleCoverage");
    gl3wCompressedTexImage3D = (PFNGLCOMPRESSEDTEXIMAGE3DPROC) get_proc("glCompressedTexImage3D");
    gl3wCompressedTexImage2D = (PFNGLCOMPRESSEDTEXIMAGE2DPROC) get_proc("glCompressedTexImage2D");
    gl3wCompressedTexImage1D = (PFNGLCOMPRESSEDTEXIMAGE1DPROC) get_proc("glCompressedTexImage1D");
    gl3wCompressedTexSubImage3D = (PFNGLCOMPRESSEDTEXSUBIMAGE3DPROC) get_proc("glCompressedTexSubImage3D");
    gl3wCompressedTexSubImage2D = (PFNGLCOMPRESSEDTEXSUBIMAGE2DPROC) get_proc("glCompressedTexSubImage2D");
    gl3wCompressedTexSubImage1D = (PFNGLCOMPRESSEDTEXSUBIMAGE1DPROC) get_proc("glCompressedTexSubImage1D");
    gl3wGetCompressedTexImage = (PFNGLGETCOMPRESSEDTEXIMAGEPROC) get_proc("glGetCompressedTexImage");
    gl3wBlendFuncSeparate = (PFNGLBLENDFUNCSEPARATEPROC) get_proc("glBlendFuncSeparate");
    gl3wMultiDrawArrays = (PFNGLMULTIDRAWARRAYSPROC) get_proc("glMultiDrawArrays");
    gl3wMultiDrawElements = (PFNGLMULTIDRAWELEMENTSPROC) get_proc("glMultiDrawElements");
    gl3wPointParameterf = (PFNGLPOINTPARAMETERFPROC) get_proc("glPointParameterf");
    gl3wPointParameterfv = (PFNGLPOINTPARAMETERFVPROC) get_proc("glPointParameterfv");
    gl3wPointParameteri = (PFNGLPOINTPARAMETERIPROC) get_proc("glPointParameteri");
    gl3wPointParameteriv = (PFNGLPOINTPARAMETERIVPROC) get_proc("glPointParameteriv");
    gl3wGenQueries = (PFNGLGENQUERIESPROC) get_proc("glGenQueries");
    gl3wDeleteQueries = (PFNGLDELETEQUERIESPROC) get_proc("glDeleteQueries");
    gl3wIsQuery = (PFNGLISQUERYPROC) get_proc("glIsQuery");
    gl3wBeginQuery = (PFNGLBEGINQUERYPROC) get_proc("glBeginQuery");
    gl3wEndQuery = (PFNGLENDQUERYPROC) get_proc("glEndQuery");
    gl3wGetQueryiv = (PFNGLGETQUERYIVPROC) get_proc("glGetQueryiv");
    gl3wGetQueryObjectiv = (PFNGLGETQUERYOBJECTIVPROC) get_proc("glGetQueryObjectiv");
    gl3wGetQueryObjectuiv = (PFNGLGETQUERYOBJECTUIVPROC) get_proc("glGetQueryObjectuiv");
    gl3wBindBuffer = (PFNGLBINDBUFFERPROC) get_proc("glBindBuffer");
    gl3wDeleteBuffers = (PFNGLDELETEBUFFERSPROC) get_proc("glDeleteBuffers");
    gl3wGenBuffers = (PFNGLGENBUFFERSPROC) get_proc("glGenBuffers");
    gl3wIsBuffer = (PFNGLISBUFFERPROC) get_proc("glIsBuffer");
    gl3wBufferData = (PFNGLBUFFERDATAPROC) get_proc("glBufferData");
    gl3wBufferSubData = (PFNGLBUFFERSUBDATAPROC) get_proc("glBufferSubData");
    gl3wGetBufferSubData = (PFNGLGETBUFFERSUBDATAPROC) get_proc("glGetBufferSubData");
    gl3wMapBuffer = (PFNGLMAPBUFFERPROC) get_proc("glMapBuffer");
    gl3wUnmapBuffer = (PFNGLUNMAPBUFFERPROC) get_proc("glUnmapBuffer");
    gl3wGetBufferParameteriv = (PFNGLGETBUFFERPARAMETERIVPROC) get_proc("glGetBufferParameteriv");
    gl3wGetBufferPointerv = (PFNGLGETBUFFERPOINTERVPROC) get_proc("glGetBufferPointerv");
    gl3wBlendEquationSeparate = (PFNGLBLENDEQUATIONSEPARATEPROC) get_proc("glBlendEquationSeparate");
    gl3wDrawBuffers = (PFNGLDRAWBUFFERSPROC) get_proc("glDrawBuffers");
    gl3wStencilOpSeparate = (PFNGLSTENCILOPSEPARATEPROC) get_proc("glStencilOpSeparate");
    gl3wStencilFuncSeparate = (PFNGLSTENCILFUNCSEPARATEPROC) get_proc("glStencilFuncSeparate");
    gl3wStencilMaskSeparate = (PFNGLSTENCILMASKSEPARATEPROC) get_proc("glStencilMaskSeparate");
    gl3wAttachShader = (PFNGLATTACHSHADERPROC) get_proc("glAttachShader");
    gl3wBindAttribLocation = (PFNGLBINDATTRIBLOCATIONPROC) get_proc("glBindAttribLocation");
    gl3wCompileShader = (PFNGLCOMPILESHADERPROC) get_proc("glCompileShader");
    gl3wCreateProgram = (PFNGLCREATEPROGRAMPROC) get_proc("glCreateProgram");
    gl3wCreateShader = (PFNGLCREATESHADERPROC) get_proc("glCreateShader");
    gl3wDeleteProgram = (PFNGLDELETEPROGRAMPROC) get_proc("glDeleteProgram");
    gl3wDeleteShader = (PFNGLDELETESHADERPROC) get_proc("glDeleteShader");
    gl3wDetachShader = (PFNGLDETACHSHADERPROC) get_proc("glDetachShader");
    gl3wDisableVertexAttribArray = (PFNGLDISABLEVERTEXATTRIBARRAYPROC) get_proc("glDisableVertexAttribArray");
    gl3wEnableVertexAttribArray = (PFNGLENABLEVERTEXATTRIBARRAYPROC) get_proc("glEnableVertexAttribArray");
    gl3wGetActiveAttrib = (PFNGLGETACTIVEATTRIBPROC) get_proc("glGetActiveAttrib");
    gl3wGetActiveUniform = (PFNGLGETACTIVEUNIFORMPROC) get_proc("glGetActiveUniform");
    gl3wGetAttachedShaders = (PFNGLGETATTACHEDSHADERSPROC) get_proc("glGetAttachedShaders");
    gl3wGetAttribLocation = (PFNGLGETATTRIBLOCATIONPROC) get_proc("glGetAttribLocation");
    gl3wGetProgramiv = (PFNGLGETPROGRAMIVPROC) get_proc("glGetProgramiv");
    gl3wGetProgramInfoLog = (PFNGLGETPROGRAMINFOLOGPROC) get_proc("glGetProgramInfoLog");
    gl3wGetShaderiv = (PFNGLGETSHADERIVPROC) get_proc("glGetShaderiv");
    gl3wGetShaderInfoLog = (PFNGLGETSHADERINFOLOGPROC) get_proc("glGetShaderInfoLog");
    gl3wGetShaderSource = (PFNGLGETSHADERSOURCEPROC) get_proc("glGetShaderSource");
    gl3wGetUniformLocation = (PFNGLGETUNIFORMLOCATIONPROC) get_proc("glGetUniformLocation");
    gl3wGetUniformfv = (PFNGLGETUNIFORMFVPROC) get_proc("glGetUniformfv");
    gl3wGetUniformiv = (PFNGLGETUNIFORMIVPROC) get_proc("glGetUniformiv");
    gl3wGetVertexAttribdv = (PFNGLGETVERTEXATTRIBDVPROC) get_proc("glGetVertexAttribdv");
    gl3wGetVertexAttribfv = (PFNGLGETVERTEXATTRIBFVPROC) get_proc("glGetVertexAttribfv");
    gl3wGetVertexAttribiv = (PFNGLGETVERTEXATTRIBIVPROC) get_proc("glGetVertexAttribiv");
    gl3wGetVertexAttribPointerv = (PFNGLGETVERTEXATTRIBPOINTERVPROC) get_proc("glGetVertexAttribPointerv");
    gl3wIsProgram = (PFNGLISPROGRAMPROC) get_proc("glIsProgram");
    gl3wIsShader = (PFNGLISSHADERPROC) get_proc("glIsShader");
    gl3wLinkProgram = (PFNGLLINKPROGRAMPROC) get_proc("glLinkProgram");
    gl3wShaderSource = (PFNGLSHADERSOURCEPROC) get_proc("glShaderSource");
    gl3wUseProgram = (PFNGLUSEPROGRAMPROC) get_proc("glUseProgram");
    gl3wUniform1f = (PFNGLUNIFORM1FPROC) get_proc("glUniform1f");
    gl3wUniform2f = (PFNGLUNIFORM2FPROC) get_proc("glUniform2f");
    gl3wUniform3f = (PFNGLUNIFORM3FPROC) get_proc("glUniform3f");
    gl3wUniform4f = (PFNGLUNIFORM4FPROC) get_proc("glUniform4f");
    gl3wUniform1i = (PFNGLUNIFORM1IPROC) get_proc("glUniform1i");
    gl3wUniform2i = (PFNGLUNIFORM2IPROC) get_proc("glUniform2i");
    gl3wUniform3i = (PFNGLUNIFORM3IPROC) get_proc("glUniform3i");
    gl3wUniform4i = (PFNGLUNIFORM4IPROC) get_proc("glUniform4i");
    gl3wUniform1fv = (PFNGLUNIFORM1FVPROC) get_proc("glUniform1fv");
    gl3wUniform2fv = (PFNGLUNIFORM2FVPROC) get_proc("glUniform2fv");
    gl3wUniform3fv = (PFNGLUNIFORM3FVPROC) get_proc("glUniform3fv");
    gl3wUniform4fv = (PFNGLUNIFORM4FVPROC) get_proc("glUniform4fv");
    gl3wUniform1iv = (PFNGLUNIFORM1IVPROC) get_proc("glUniform1iv");
    gl3wUniform2iv = (PFNGLUNIFORM2IVPROC) get_proc("glUniform2iv");
    gl3wUniform3iv = (PFNGLUNIFORM3IVPROC) get_proc("glUniform3iv");
    gl3wUniform4iv = (PFNGLUNIFORM4IVPROC) get_proc("glUniform4iv");
    gl3wUniformMatrix2fv = (PFNGLUNIFORMMATRIX2FVPROC) get_proc("glUniformMatrix2fv");
    gl3wUniformMatrix3fv = (PFNGLUNIFORMMATRIX3FVPROC) get_proc("glUniformMatrix3fv");
    gl3wUniformMatrix4fv = (PFNGLUNIFORMMATRIX4FVPROC) get_proc("glUniformMatrix4fv");
    gl3wValidateProgram = (PFNGLVALIDATEPROGRAMPROC) get_proc("glValidateProgram");
    gl3wVertexAttrib1d = (PFNGLVERTEXATTRIB1DPROC) get_proc("glVertexAttrib1d");
    gl3wVertexAttrib1dv = (PFNGLVERTEXATTRIB1DVPROC) get_proc("glVertexAttrib1dv");
    gl3wVertexAttrib1f = (PFNGLVERTEXATTRIB1FPROC) get_proc("glVertexAttrib1f");
    gl3wVertexAttrib1fv = (PFNGLVERTEXATTRIB1FVPROC) get_proc("glVertexAttrib1fv");
    gl3wVertexAttrib1s = (PFNGLVERTEXATTRIB1SPROC) get_proc("glVertexAttrib1s");
    gl3wVertexAttrib1sv = (PFNGLVERTEXATTRIB1SVPROC) get_proc("glVertexAttrib1sv");
    gl3wVertexAttrib2d = (PFNGLVERTEXATTRIB2DPROC) get_proc("glVertexAttrib2d");
    gl3wVertexAttrib2dv = (PFNGLVERTEXATTRIB2DVPROC) get_proc("glVertexAttrib2dv");
    gl3wVertexAttrib2f = (PFNGLVERTEXATTRIB2FPROC) get_proc("glVertexAttrib2f");
    gl3wVertexAttrib2fv = (PFNGLVERTEXATTRIB2FVPROC) get_proc("glVertexAttrib2fv");
    gl3wVertexAttrib2s = (PFNGLVERTEXATTRIB2SPROC) get_proc("glVertexAttrib2s");
    gl3wVertexAttrib2sv = (PFNGLVERTEXATTRIB2SVPROC) get_proc("glVertexAttrib2sv");
    gl3wVertexAttrib3d = (PFNGLVERTEXATTRIB3DPROC) get_proc("glVertexAttrib3d");
    gl3wVertexAttrib3dv = (PFNGLVERTEXATTRIB3DVPROC) get_proc("glVertexAttrib3dv");
    gl3wVertexAttrib3f = (PFNGLVERTEXATTRIB3FPROC) get_proc("glVertexAttrib3f");
    gl3wVertexAttrib3fv = (PFNGLVERTEXATTRIB3FVPROC) get_proc("glVertexAttrib3fv");
    gl3wVertexAttrib3s = (PFNGLVERTEXATTRIB3SPROC) get_proc("glVertexAttrib3s");
    gl3wVertexAttrib3sv = (PFNGLVERTEXATTRIB3SVPROC) get_proc("glVertexAttrib3sv");
    gl3wVertexAttrib4Nbv = (PFNGLVERTEXATTRIB4NBVPROC) get_proc("glVertexAttrib4Nbv");
    gl3wVertexAttrib4Niv = (PFNGLVERTEXATTRIB4NIVPROC) get_proc("glVertexAttrib4Niv");
    gl3wVertexAttrib4Nsv = (PFNGLVERTEXATTRIB4NSVPROC) get_proc("glVertexAttrib4Nsv");
    gl3wVertexAttrib4Nub = (PFNGLVERTEXATTRIB4NUBPROC) get_proc("glVertexAttrib4Nub");
    gl3wVertexAttrib4Nubv = (PFNGLVERTEXATTRIB4NUBVPROC) get_proc("glVertexAttrib4Nubv");
    gl3wVertexAttrib4Nuiv = (PFNGLVERTEXATTRIB4NUIVPROC) get_proc("glVertexAttrib4Nuiv");
    gl3wVertexAttrib4Nusv = (PFNGLVERTEXATTRIB4NUSVPROC) get_proc("glVertexAttrib4Nusv");
    gl3wVertexAttrib4bv = (PFNGLVERTEXATTRIB4BVPROC) get_proc("glVertexAttrib4bv");
    gl3wVertexAttrib4d = (PFNGLVERTEXATTRIB4DPROC) get_proc("glVertexAttrib4d");
    gl3wVertexAttrib4dv = (PFNGLVERTEXATTRIB4DVPROC) get_proc("glVertexAttrib4dv");
    gl3wVertexAttrib4f = (PFNGLVERTEXATTRIB4FPROC) get_proc("glVertexAttrib4f");
    gl3wVertexAttrib4fv = (PFNGLVERTEXATTRIB4FVPROC) get_proc("glVertexAttrib4fv");
    gl3wVertexAttrib4iv = (PFNGLVERTEXATTRIB4IVPROC) get_proc("glVertexAttrib4iv");
    gl3wVertexAttrib4s = (PFNGLVERTEXATTRIB4SPROC) get_proc("glVertexAttrib4s");
    gl3wVertexAttrib4sv = (PFNGLVERTEXATTRIB4SVPROC) get_proc("glVertexAttrib4sv");
    gl3wVertexAttrib4ubv = (PFNGLVERTEXATTRIB4UBVPROC) get_proc("glVertexAttrib4ubv");
    gl3wVertexAttrib4uiv = (PFNGLVERTEXATTRIB4UIVPROC) get_proc("glVertexAttrib4uiv");
    gl3wVertexAttrib4usv = (PFNGLVERTEXATTRIB4USVPROC) get_proc("glVertexAttrib4usv");
    gl3wVertexAttribPointer = (PFNGLVERTEXATTRIBPOINTERPROC) get_proc("glVertexAttribPointer");
    gl3wUniformMatrix2x3fv = (PFNGLUNIFORMMATRIX2X3FVPROC) get_proc("glUniformMatrix2x3fv");
    gl3wUniformMatrix3x2fv = (PFNGLUNIFORMMATRIX3X2FVPROC) get_proc("glUniformMatrix3x2fv");
    gl3wUniformMatrix2x4fv = (PFNGLUNIFORMMATRIX2X4FVPROC) get_proc("glUniformMatrix2x4fv");
    gl3wUniformMatrix4x2fv = (PFNGLUNIFORMMATRIX4X2FVPROC) get_proc("glUniformMatrix4x2fv");
    gl3wUniformMatrix3x4fv = (PFNGLUNIFORMMATRIX3X4FVPROC) get_proc("glUniformMatrix3x4fv");
    gl3wUniformMatrix4x3fv = (PFNGLUNIFORMMATRIX4X3FVPROC) get_proc("glUniformMatrix4x3fv");
    gl3wColorMaski = (PFNGLCOLORMASKIPROC) get_proc("glColorMaski");
    gl3wGetBooleani_v = (PFNGLGETBOOLEANI_VPROC) get_proc("glGetBooleani_v");
    gl3wGetIntegeri_v = (PFNGLGETINTEGERI_VPROC) get_proc("glGetIntegeri_v");
    gl3wEnablei = (PFNGLENABLEIPROC) get_proc("glEnablei");
    gl3wDisablei = (PFNGLDISABLEIPROC) get_proc("glDisablei");
    gl3wIsEnabledi = (PFNGLISENABLEDIPROC) get_proc("glIsEnabledi");
    gl3wBeginTransformFeedback = (PFNGLBEGINTRANSFORMFEEDBACKPROC) get_proc("glBeginTransformFeedback");
    gl3wEndTransformFeedback = (PFNGLENDTRANSFORMFEEDBACKPROC) get_proc("glEndTransformFeedback");
    gl3wBindBufferRange = (PFNGLBINDBUFFERRANGEPROC) get_proc("glBindBufferRange");
    gl3wBindBufferBase = (PFNGLBINDBUFFERBASEPROC) get_proc("glBindBufferBase");
    gl3wTransformFeedbackVaryings = (PFNGLTRANSFORMFEEDBACKVARYINGSPROC) get_proc("glTransformFeedbackVaryings");
    gl3wGetTransformFeedbackVarying = (PFNGLGETTRANSFORMFEEDBACKVARYINGPROC) get_proc("glGetTransformFeedbackVarying");
    gl3wClampColor = (PFNGLCLAMPCOLORPROC) get_proc("glClampColor");
    gl3wBeginConditionalRender = (PFNGLBEGINCONDITIONALRENDERPROC) get_proc("glBeginConditionalRender");
    gl3wEndConditionalRender = (PFNGLENDCONDITIONALRENDERPROC) get_proc("glEndConditionalRender");
    gl3wVertexAttribIPointer = (PFNGLVERTEXATTRIBIPOINTERPROC) get_proc("glVertexAttribIPointer");
    gl3wGetVertexAttribIiv = (PFNGLGETVERTEXATTRIBIIVPROC) get_proc("glGetVertexAttribIiv");
    gl3wGetVertexAttribIuiv = (PFNGLGETVERTEXATTRIBIUIVPROC) get_proc("glGetVertexAttribIuiv");
    gl3wVertexAttribI1i = (PFNGLVERTEXATTRIBI1IPROC) get_proc("glVertexAttribI1i");
    gl3wVertexAttribI2i = (PFNGLVERTEXATTRIBI2IPROC) get_proc("glVertexAttribI2i");
    gl3wVertexAttribI3i = (PFNGLVERTEXATTRIBI3IPROC) get_proc("glVertexAttribI3i");
    gl3wVertexAttribI4i = (PFNGLVERTEXATTRIBI4IPROC) get_proc("glVertexAttribI4i");
    gl3wVertexAttribI1ui = (PFNGLVERTEXATTRIBI1UIPROC) get_proc("glVertexAttribI1ui");
    gl3wVertexAttribI2ui = (PFNGLVERTEXATTRIBI2UIPROC) get_proc("glVertexAttribI2ui");
    gl3wVertexAttribI3ui = (PFNGLVERTEXATTRIBI3UIPROC) get_proc("glVertexAttribI3ui");
    gl3wVertexAttribI4ui = (PFNGLVERTEXATTRIBI4UIPROC) get_proc("glVertexAttribI4ui");
    gl3wVertexAttribI1iv = (PFNGLVERTEXATTRIBI1IVPROC) get_proc("glVertexAttribI1iv");
    gl3wVertexAttribI2iv = (PFNGLVERTEXATTRIBI2IVPROC) get_proc("glVertexAttribI2iv");
    gl3wVertexAttribI3iv = (PFNGLVERTEXATTRIBI3IVPROC) get_proc("glVertexAttribI3iv");
    gl3wVertexAttribI4iv = (PFNGLVERTEXATTRIBI4IVPROC) get_proc("glVertexAttribI4iv");
    gl3wVertexAttribI1uiv = (PFNGLVERTEXATTRIBI1UIVPROC) get_proc("glVertexAttribI1uiv");
    gl3wVertexAttribI2uiv = (PFNGLVERTEXATTRIBI2UIVPROC) get_proc("glVertexAttribI2uiv");
    gl3wVertexAttribI3uiv = (PFNGLVERTEXATTRIBI3UIVPROC) get_proc("glVertexAttribI3uiv");
    gl3wVertexAttribI4uiv = (PFNGLVERTEXATTRIBI4UIVPROC) get_proc("glVertexAttribI4uiv");
    gl3wVertexAttribI4bv = (PFNGLVERTEXATTRIBI4BVPROC) get_proc("glVertexAttribI4bv");
    gl3wVertexAttribI4sv = (PFNGLVERTEXATTRIBI4SVPROC) get_proc("glVertexAttribI4sv");
    gl3wVertexAttribI4ubv = (PFNGLVERTEXATTRIBI4UBVPROC) get_proc("glVertexAttribI4ubv");
    gl3wVertexAttribI4usv = (PFNGLVERTEXATTRIBI4USVPROC) get_proc("glVertexAttribI4usv");
    gl3wGetUniformuiv = (PFNGLGETUNIFORMUIVPROC) get_proc("glGetUniformuiv");
    gl3wBindFragDataLocation = (PFNGLBINDFRAGDATALOCATIONPROC) get_proc("glBindFragDataLocation");
    gl3wGetFragDataLocation = (PFNGLGETFRAGDATALOCATIONPROC) get_proc("glGetFragDataLocation");
    gl3wUniform1ui = (PFNGLUNIFORM1UIPROC) get_proc("glUniform1ui");
    gl3wUniform2ui = (PFNGLUNIFORM2UIPROC) get_proc("glUniform2ui");
    gl3wUniform3ui = (PFNGLUNIFORM3UIPROC) get_proc("glUniform3ui");
    gl3wUniform4ui = (PFNGLUNIFORM4UIPROC) get_proc("glUniform4ui");
    gl3wUniform1uiv = (PFNGLUNIFORM1UIVPROC) get_proc("glUniform1uiv");
    gl3wUniform2uiv = (PFNGLUNIFORM2UIVPROC) get_proc("glUniform2uiv");
    gl3wUniform3uiv = (PFNGLUNIFORM3UIVPROC) get_proc("glUniform3uiv");
    gl3wUniform4uiv = (PFNGLUNIFORM4UIVPROC) get_proc("glUniform4uiv");
    gl3wTexParameterIiv = (PFNGLTEXPARAMETERIIVPROC) get_proc("glTexParameterIiv");
    gl3wTexParameterIuiv = (PFNGLTEXPARAMETERIUIVPROC) get_proc("glTexParameterIuiv");
    gl3wGetTexParameterIiv = (PFNGLGETTEXPARAMETERIIVPROC) get_proc("glGetTexParameterIiv");
    gl3wGetTexParameterIuiv = (PFNGLGETTEXPARAMETERIUIVPROC) get_proc("glGetTexParameterIuiv");
    gl3wClearBufferiv = (PFNGLCLEARBUFFERIVPROC) get_proc("glClearBufferiv");
    gl3wClearBufferuiv = (PFNGLCLEARBUFFERUIVPROC) get_proc("glClearBufferuiv");
    gl3wClearBufferfv = (PFNGLCLEARBUFFERFVPROC) get_proc("glClearBufferfv");
    gl3wClearBufferfi = (PFNGLCLEARBUFFERFIPROC) get_proc("glClearBufferfi");
    gl3wGetStringi = (PFNGLGETSTRINGIPROC) get_proc("glGetStringi");
    gl3wDrawArraysInstanced = (PFNGLDRAWARRAYSINSTANCEDPROC) get_proc("glDrawArraysInstanced");
    gl3wDrawElementsInstanced = (PFNGLDRAWELEMENTSINSTANCEDPROC) get_proc("glDrawElementsInstanced");
    gl3wTexBuffer = (PFNGLTEXBUFFERPROC) get_proc("glTexBuffer");
    gl3wPrimitiveRestartIndex = (PFNGLPRIMITIVERESTARTINDEXPROC) get_proc("glPrimitiveRestartIndex");
    gl3wGetInteger64i_v = (PFNGLGETINTEGER64I_VPROC) get_proc("glGetInteger64i_v");
    gl3wGetBufferParameteri64v = (PFNGLGETBUFFERPARAMETERI64VPROC) get_proc("glGetBufferParameteri64v");
    gl3wFramebufferTexture = (PFNGLFRAMEBUFFERTEXTUREPROC) get_proc("glFramebufferTexture");
    gl3wVertexAttribDivisor = (PFNGLVERTEXATTRIBDIVISORPROC) get_proc("glVertexAttribDivisor");
    gl3wMinSampleShading = (PFNGLMINSAMPLESHADINGPROC) get_proc("glMinSampleShading");
    gl3wBlendEquationi = (PFNGLBLENDEQUATIONIPROC) get_proc("glBlendEquationi");
    gl3wBlendEquationSeparatei = (PFNGLBLENDEQUATIONSEPARATEIPROC) get_proc("glBlendEquationSeparatei");
    gl3wBlendFunci = (PFNGLBLENDFUNCIPROC) get_proc("glBlendFunci");
    gl3wBlendFuncSeparatei = (PFNGLBLENDFUNCSEPARATEIPROC) get_proc("glBlendFuncSeparatei");
    gl3wIsRenderbuffer = (PFNGLISRENDERBUFFERPROC) get_proc("glIsRenderbuffer");
    gl3wBindRenderbuffer = (PFNGLBINDRENDERBUFFERPROC) get_proc("glBindRenderbuffer");
    gl3wDeleteRenderbuffers = (PFNGLDELETERENDERBUFFERSPROC) get_proc("glDeleteRenderbuffers");
    gl3wGenRenderbuffers = (PFNGLGENRENDERBUFFERSPROC) get_proc("glGenRenderbuffers");
    gl3wRenderbufferStorage = (PFNGLRENDERBUFFERSTORAGEPROC) get_proc("glRenderbufferStorage");
    gl3wGetRenderbufferParameteriv = (PFNGLGETRENDERBUFFERPARAMETERIVPROC) get_proc("glGetRenderbufferParameteriv");
    gl3wIsFramebuffer = (PFNGLISFRAMEBUFFERPROC) get_proc("glIsFramebuffer");
    gl3wBindFramebuffer = (PFNGLBINDFRAMEBUFFERPROC) get_proc("glBindFramebuffer");
    gl3wDeleteFramebuffers = (PFNGLDELETEFRAMEBUFFERSPROC) get_proc("glDeleteFramebuffers");
    gl3wGenFramebuffers = (PFNGLGENFRAMEBUFFERSPROC) get_proc("glGenFramebuffers");
    gl3wCheckFramebufferStatus = (PFNGLCHECKFRAMEBUFFERSTATUSPROC) get_proc("glCheckFramebufferStatus");
    gl3wFramebufferTexture1D = (PFNGLFRAMEBUFFERTEXTURE1DPROC) get_proc("glFramebufferTexture1D");
    gl3wFramebufferTexture2D = (PFNGLFRAMEBUFFERTEXTURE2DPROC) get_proc("glFramebufferTexture2D");
    gl3wFramebufferTexture3D = (PFNGLFRAMEBUFFERTEXTURE3DPROC) get_proc("glFramebufferTexture3D");
    gl3wFramebufferRenderbuffer = (PFNGLFRAMEBUFFERRENDERBUFFERPROC) get_proc("glFramebufferRenderbuffer");
    gl3wGetFramebufferAttachmentParameteriv = (PFNGLGETFRAMEBUFFERATTACHMENTPARAMETERIVPROC) get_proc("glGetFramebufferAttachmentParameteriv");
    gl3wGenerateMipmap = (PFNGLGENERATEMIPMAPPROC) get_proc("glGenerateMipmap");
    gl3wBlitFramebuffer = (PFNGLBLITFRAMEBUFFERPROC) get_proc("glBlitFramebuffer");
    gl3wRenderbufferStorageMultisample = (PFNGLRENDERBUFFERSTORAGEMULTISAMPLEPROC) get_proc("glRenderbufferStorageMultisample");
    gl3wFramebufferTextureLayer = (PFNGLFRAMEBUFFERTEXTURELAYERPROC) get_proc("glFramebufferTextureLayer");
    gl3wMapBufferRange = (PFNGLMAPBUFFERRANGEPROC) get_proc("glMapBufferRange");
    gl3wFlushMappedBufferRange = (PFNGLFLUSHMAPPEDBUFFERRANGEPROC) get_proc("glFlushMappedBufferRange");
    gl3wBindVertexArray = (PFNGLBINDVERTEXARRAYPROC) get_proc("glBindVertexArray");
    gl3wDeleteVertexArrays = (PFNGLDELETEVERTEXARRAYSPROC) get_proc("glDeleteVertexArrays");
    gl3wGenVertexArrays = (PFNGLGENVERTEXARRAYSPROC) get_proc("glGenVertexArrays");
    gl3wIsVertexArray = (PFNGLISVERTEXARRAYPROC) get_proc("glIsVertexArray");
    gl3wGetUniformIndices = (PFNGLGETUNIFORMINDICESPROC) get_proc("glGetUniformIndices");
    gl3wGetActiveUniformsiv = (PFNGLGETACTIVEUNIFORMSIVPROC) get_proc("glGetActiveUniformsiv");
    gl3wGetActiveUniformName = (PFNGLGETACTIVEUNIFORMNAMEPROC) get_proc("glGetActiveUniformName");
    gl3wGetUniformBlockIndex = (PFNGLGETUNIFORMBLOCKINDEXPROC) get_proc("glGetUniformBlockIndex");
    gl3wGetActiveUniformBlockiv = (PFNGLGETACTIVEUNIFORMBLOCKIVPROC) get_proc("glGetActiveUniformBlockiv");
    gl3wGetActiveUniformBlockName = (PFNGLGETACTIVEUNIFORMBLOCKNAMEPROC) get_proc("glGetActiveUniformBlockName");
    gl3wUniformBlockBinding = (PFNGLUNIFORMBLOCKBINDINGPROC) get_proc("glUniformBlockBinding");
    gl3wCopyBufferSubData = (PFNGLCOPYBUFFERSUBDATAPROC) get_proc("glCopyBufferSubData");
    gl3wDrawElementsBaseVertex = (PFNGLDRAWELEMENTSBASEVERTEXPROC) get_proc("glDrawElementsBaseVertex");
    gl3wDrawRangeElementsBaseVertex = (PFNGLDRAWRANGEELEMENTSBASEVERTEXPROC) get_proc("glDrawRangeElementsBaseVertex");
    gl3wDrawElementsInstancedBaseVertex = (PFNGLDRAWELEMENTSINSTANCEDBASEVERTEXPROC) get_proc("glDrawElementsInstancedBaseVertex");
    gl3wMultiDrawElementsBaseVertex = (PFNGLMULTIDRAWELEMENTSBASEVERTEXPROC) get_proc("glMultiDrawElementsBaseVertex");
    gl3wProvokingVertex = (PFNGLPROVOKINGVERTEXPROC) get_proc("glProvokingVertex");
    gl3wFenceSync = (PFNGLFENCESYNCPROC) get_proc("glFenceSync");
    gl3wIsSync = (PFNGLISSYNCPROC) get_proc("glIsSync");
    gl3wDeleteSync = (PFNGLDELETESYNCPROC) get_proc("glDeleteSync");
    gl3wClientWaitSync = (PFNGLCLIENTWAITSYNCPROC) get_proc("glClientWaitSync");
    gl3wWaitSync = (PFNGLWAITSYNCPROC) get_proc("glWaitSync");
    gl3wGetInteger64v = (PFNGLGETINTEGER64VPROC) get_proc("glGetInteger64v");
    gl3wGetSynciv = (PFNGLGETSYNCIVPROC) get_proc("glGetSynciv");
    gl3wTexImage2DMultisample = (PFNGLTEXIMAGE2DMULTISAMPLEPROC) get_proc("glTexImage2DMultisample");
    gl3wTexImage3DMultisample = (PFNGLTEXIMAGE3DMULTISAMPLEPROC) get_proc("glTexImage3DMultisample");
    gl3wGetMultisamplefv = (PFNGLGETMULTISAMPLEFVPROC) get_proc("glGetMultisamplefv");
    gl3wSampleMaski = (PFNGLSAMPLEMASKIPROC) get_proc("glSampleMaski");
    gl3wBlendEquationiARB = (PFNGLBLENDEQUATIONIARBPROC) get_proc("glBlendEquationiARB");
    gl3wBlendEquationSeparateiARB = (PFNGLBLENDEQUATIONSEPARATEIARBPROC) get_proc("glBlendEquationSeparateiARB");
    gl3wBlendFunciARB = (PFNGLBLENDFUNCIARBPROC) get_proc("glBlendFunciARB");
    gl3wBlendFuncSeparateiARB = (PFNGLBLENDFUNCSEPARATEIARBPROC) get_proc("glBlendFuncSeparateiARB");
    gl3wMinSampleShadingARB = (PFNGLMINSAMPLESHADINGARBPROC) get_proc("glMinSampleShadingARB");
    gl3wNamedStringARB = (PFNGLNAMEDSTRINGARBPROC) get_proc("glNamedStringARB");
    gl3wDeleteNamedStringARB = (PFNGLDELETENAMEDSTRINGARBPROC) get_proc("glDeleteNamedStringARB");
    gl3wCompileShaderIncludeARB = (PFNGLCOMPILESHADERINCLUDEARBPROC) get_proc("glCompileShaderIncludeARB");
    gl3wIsNamedStringARB = (PFNGLISNAMEDSTRINGARBPROC) get_proc("glIsNamedStringARB");
    gl3wGetNamedStringARB = (PFNGLGETNAMEDSTRINGARBPROC) get_proc("glGetNamedStringARB");
    gl3wGetNamedStringivARB = (PFNGLGETNAMEDSTRINGIVARBPROC) get_proc("glGetNamedStringivARB");
    gl3wBindFragDataLocationIndexed = (PFNGLBINDFRAGDATALOCATIONINDEXEDPROC) get_proc("glBindFragDataLocationIndexed");
    gl3wGetFragDataIndex = (PFNGLGETFRAGDATAINDEXPROC) get_proc("glGetFragDataIndex");
    gl3wGenSamplers = (PFNGLGENSAMPLERSPROC) get_proc("glGenSamplers");
    gl3wDeleteSamplers = (PFNGLDELETESAMPLERSPROC) get_proc("glDeleteSamplers");
    gl3wIsSampler = (PFNGLISSAMPLERPROC) get_proc("glIsSampler");
    gl3wBindSampler = (PFNGLBINDSAMPLERPROC) get_proc("glBindSampler");
    gl3wSamplerParameteri = (PFNGLSAMPLERPARAMETERIPROC) get_proc("glSamplerParameteri");
    gl3wSamplerParameteriv = (PFNGLSAMPLERPARAMETERIVPROC) get_proc("glSamplerParameteriv");
    gl3wSamplerParameterf = (PFNGLSAMPLERPARAMETERFPROC) get_proc("glSamplerParameterf");
    gl3wSamplerParameterfv = (PFNGLSAMPLERPARAMETERFVPROC) get_proc("glSamplerParameterfv");
    gl3wSamplerParameterIiv = (PFNGLSAMPLERPARAMETERIIVPROC) get_proc("glSamplerParameterIiv");
    gl3wSamplerParameterIuiv = (PFNGLSAMPLERPARAMETERIUIVPROC) get_proc("glSamplerParameterIuiv");
    gl3wGetSamplerParameteriv = (PFNGLGETSAMPLERPARAMETERIVPROC) get_proc("glGetSamplerParameteriv");
    gl3wGetSamplerParameterIiv = (PFNGLGETSAMPLERPARAMETERIIVPROC) get_proc("glGetSamplerParameterIiv");
    gl3wGetSamplerParameterfv = (PFNGLGETSAMPLERPARAMETERFVPROC) get_proc("glGetSamplerParameterfv");
    gl3wGetSamplerParameterIuiv = (PFNGLGETSAMPLERPARAMETERIUIVPROC) get_proc("glGetSamplerParameterIuiv");
    gl3wQueryCounter = (PFNGLQUERYCOUNTERPROC) get_proc("glQueryCounter");
    gl3wGetQueryObjecti64v = (PFNGLGETQUERYOBJECTI64VPROC) get_proc("glGetQueryObjecti64v");
    gl3wGetQueryObjectui64v = (PFNGLGETQUERYOBJECTUI64VPROC) get_proc("glGetQueryObjectui64v");
    gl3wVertexP2ui = (PFNGLVERTEXP2UIPROC) get_proc("glVertexP2ui");
    gl3wVertexP2uiv = (PFNGLVERTEXP2UIVPROC) get_proc("glVertexP2uiv");
    gl3wVertexP3ui = (PFNGLVERTEXP3UIPROC) get_proc("glVertexP3ui");
    gl3wVertexP3uiv = (PFNGLVERTEXP3UIVPROC) get_proc("glVertexP3uiv");
    gl3wVertexP4ui = (PFNGLVERTEXP4UIPROC) get_proc("glVertexP4ui");
    gl3wVertexP4uiv = (PFNGLVERTEXP4UIVPROC) get_proc("glVertexP4uiv");
    gl3wTexCoordP1ui = (PFNGLTEXCOORDP1UIPROC) get_proc("glTexCoordP1ui");
    gl3wTexCoordP1uiv = (PFNGLTEXCOORDP1UIVPROC) get_proc("glTexCoordP1uiv");
    gl3wTexCoordP2ui = (PFNGLTEXCOORDP2UIPROC) get_proc("glTexCoordP2ui");
    gl3wTexCoordP2uiv = (PFNGLTEXCOORDP2UIVPROC) get_proc("glTexCoordP2uiv");
    gl3wTexCoordP3ui = (PFNGLTEXCOORDP3UIPROC) get_proc("glTexCoordP3ui");
    gl3wTexCoordP3uiv = (PFNGLTEXCOORDP3UIVPROC) get_proc("glTexCoordP3uiv");
    gl3wTexCoordP4ui = (PFNGLTEXCOORDP4UIPROC) get_proc("glTexCoordP4ui");
    gl3wTexCoordP4uiv = (PFNGLTEXCOORDP4UIVPROC) get_proc("glTexCoordP4uiv");
    gl3wMultiTexCoordP1ui = (PFNGLMULTITEXCOORDP1UIPROC) get_proc("glMultiTexCoordP1ui");
    gl3wMultiTexCoordP1uiv = (PFNGLMULTITEXCOORDP1UIVPROC) get_proc("glMultiTexCoordP1uiv");
    gl3wMultiTexCoordP2ui = (PFNGLMULTITEXCOORDP2UIPROC) get_proc("glMultiTexCoordP2ui");
    gl3wMultiTexCoordP2uiv = (PFNGLMULTITEXCOORDP2UIVPROC) get_proc("glMultiTexCoordP2uiv");
    gl3wMultiTexCoordP3ui = (PFNGLMULTITEXCOORDP3UIPROC) get_proc("glMultiTexCoordP3ui");
    gl3wMultiTexCoordP3uiv = (PFNGLMULTITEXCOORDP3UIVPROC) get_proc("glMultiTexCoordP3uiv");
    gl3wMultiTexCoordP4ui = (PFNGLMULTITEXCOORDP4UIPROC) get_proc("glMultiTexCoordP4ui");
    gl3wMultiTexCoordP4uiv = (PFNGLMULTITEXCOORDP4UIVPROC) get_proc("glMultiTexCoordP4uiv");
    gl3wNormalP3ui = (PFNGLNORMALP3UIPROC) get_proc("glNormalP3ui");
    gl3wNormalP3uiv = (PFNGLNORMALP3UIVPROC) get_proc("glNormalP3uiv");
    gl3wColorP3ui = (PFNGLCOLORP3UIPROC) get_proc("glColorP3ui");
    gl3wColorP3uiv = (PFNGLCOLORP3UIVPROC) get_proc("glColorP3uiv");
    gl3wColorP4ui = (PFNGLCOLORP4UIPROC) get_proc("glColorP4ui");
    gl3wColorP4uiv = (PFNGLCOLORP4UIVPROC) get_proc("glColorP4uiv");
    gl3wSecondaryColorP3ui = (PFNGLSECONDARYCOLORP3UIPROC) get_proc("glSecondaryColorP3ui");
    gl3wSecondaryColorP3uiv = (PFNGLSECONDARYCOLORP3UIVPROC) get_proc("glSecondaryColorP3uiv");
    gl3wVertexAttribP1ui = (PFNGLVERTEXATTRIBP1UIPROC) get_proc("glVertexAttribP1ui");
    gl3wVertexAttribP1uiv = (PFNGLVERTEXATTRIBP1UIVPROC) get_proc("glVertexAttribP1uiv");
    gl3wVertexAttribP2ui = (PFNGLVERTEXATTRIBP2UIPROC) get_proc("glVertexAttribP2ui");
    gl3wVertexAttribP2uiv = (PFNGLVERTEXATTRIBP2UIVPROC) get_proc("glVertexAttribP2uiv");
    gl3wVertexAttribP3ui = (PFNGLVERTEXATTRIBP3UIPROC) get_proc("glVertexAttribP3ui");
    gl3wVertexAttribP3uiv = (PFNGLVERTEXATTRIBP3UIVPROC) get_proc("glVertexAttribP3uiv");
    gl3wVertexAttribP4ui = (PFNGLVERTEXATTRIBP4UIPROC) get_proc("glVertexAttribP4ui");
    gl3wVertexAttribP4uiv = (PFNGLVERTEXATTRIBP4UIVPROC) get_proc("glVertexAttribP4uiv");
    gl3wDrawArraysIndirect = (PFNGLDRAWARRAYSINDIRECTPROC) get_proc("glDrawArraysIndirect");
    gl3wDrawElementsIndirect = (PFNGLDRAWELEMENTSINDIRECTPROC) get_proc("glDrawElementsIndirect");
    gl3wUniform1d = (PFNGLUNIFORM1DPROC) get_proc("glUniform1d");
    gl3wUniform2d = (PFNGLUNIFORM2DPROC) get_proc("glUniform2d");
    gl3wUniform3d = (PFNGLUNIFORM3DPROC) get_proc("glUniform3d");
    gl3wUniform4d = (PFNGLUNIFORM4DPROC) get_proc("glUniform4d");
    gl3wUniform1dv = (PFNGLUNIFORM1DVPROC) get_proc("glUniform1dv");
    gl3wUniform2dv = (PFNGLUNIFORM2DVPROC) get_proc("glUniform2dv");
    gl3wUniform3dv = (PFNGLUNIFORM3DVPROC) get_proc("glUniform3dv");
    gl3wUniform4dv = (PFNGLUNIFORM4DVPROC) get_proc("glUniform4dv");
    gl3wUniformMatrix2dv = (PFNGLUNIFORMMATRIX2DVPROC) get_proc("glUniformMatrix2dv");
    gl3wUniformMatrix3dv = (PFNGLUNIFORMMATRIX3DVPROC) get_proc("glUniformMatrix3dv");
    gl3wUniformMatrix4dv = (PFNGLUNIFORMMATRIX4DVPROC) get_proc("glUniformMatrix4dv");
    gl3wUniformMatrix2x3dv = (PFNGLUNIFORMMATRIX2X3DVPROC) get_proc("glUniformMatrix2x3dv");
    gl3wUniformMatrix2x4dv = (PFNGLUNIFORMMATRIX2X4DVPROC) get_proc("glUniformMatrix2x4dv");
    gl3wUniformMatrix3x2dv = (PFNGLUNIFORMMATRIX3X2DVPROC) get_proc("glUniformMatrix3x2dv");
    gl3wUniformMatrix3x4dv = (PFNGLUNIFORMMATRIX3X4DVPROC) get_proc("glUniformMatrix3x4dv");
    gl3wUniformMatrix4x2dv = (PFNGLUNIFORMMATRIX4X2DVPROC) get_proc("glUniformMatrix4x2dv");
    gl3wUniformMatrix4x3dv = (PFNGLUNIFORMMATRIX4X3DVPROC) get_proc("glUniformMatrix4x3dv");
    gl3wGetUniformdv = (PFNGLGETUNIFORMDVPROC) get_proc("glGetUniformdv");
    gl3wGetSubroutineUniformLocation = (PFNGLGETSUBROUTINEUNIFORMLOCATIONPROC) get_proc("glGetSubroutineUniformLocation");
    gl3wGetSubroutineIndex = (PFNGLGETSUBROUTINEINDEXPROC) get_proc("glGetSubroutineIndex");
    gl3wGetActiveSubroutineUniformiv = (PFNGLGETACTIVESUBROUTINEUNIFORMIVPROC) get_proc("glGetActiveSubroutineUniformiv");
    gl3wGetActiveSubroutineUniformName = (PFNGLGETACTIVESUBROUTINEUNIFORMNAMEPROC) get_proc("glGetActiveSubroutineUniformName");
    gl3wGetActiveSubroutineName = (PFNGLGETACTIVESUBROUTINENAMEPROC) get_proc("glGetActiveSubroutineName");
    gl3wUniformSubroutinesuiv = (PFNGLUNIFORMSUBROUTINESUIVPROC) get_proc("glUniformSubroutinesuiv");
    gl3wGetUniformSubroutineuiv = (PFNGLGETUNIFORMSUBROUTINEUIVPROC) get_proc("glGetUniformSubroutineuiv");
    gl3wGetProgramStageiv = (PFNGLGETPROGRAMSTAGEIVPROC) get_proc("glGetProgramStageiv");
    gl3wPatchParameteri = (PFNGLPATCHPARAMETERIPROC) get_proc("glPatchParameteri");
    gl3wPatchParameterfv = (PFNGLPATCHPARAMETERFVPROC) get_proc("glPatchParameterfv");
    gl3wBindTransformFeedback = (PFNGLBINDTRANSFORMFEEDBACKPROC) get_proc("glBindTransformFeedback");
    gl3wDeleteTransformFeedbacks = (PFNGLDELETETRANSFORMFEEDBACKSPROC) get_proc("glDeleteTransformFeedbacks");
    gl3wGenTransformFeedbacks = (PFNGLGENTRANSFORMFEEDBACKSPROC) get_proc("glGenTransformFeedbacks");
    gl3wIsTransformFeedback = (PFNGLISTRANSFORMFEEDBACKPROC) get_proc("glIsTransformFeedback");
    gl3wPauseTransformFeedback = (PFNGLPAUSETRANSFORMFEEDBACKPROC) get_proc("glPauseTransformFeedback");
    gl3wResumeTransformFeedback = (PFNGLRESUMETRANSFORMFEEDBACKPROC) get_proc("glResumeTransformFeedback");
    gl3wDrawTransformFeedback = (PFNGLDRAWTRANSFORMFEEDBACKPROC) get_proc("glDrawTransformFeedback");
    gl3wDrawTransformFeedbackStream = (PFNGLDRAWTRANSFORMFEEDBACKSTREAMPROC) get_proc("glDrawTransformFeedbackStream");
    gl3wBeginQueryIndexed = (PFNGLBEGINQUERYINDEXEDPROC) get_proc("glBeginQueryIndexed");
    gl3wEndQueryIndexed = (PFNGLENDQUERYINDEXEDPROC) get_proc("glEndQueryIndexed");
    gl3wGetQueryIndexediv = (PFNGLGETQUERYINDEXEDIVPROC) get_proc("glGetQueryIndexediv");
    gl3wReleaseShaderCompiler = (PFNGLRELEASESHADERCOMPILERPROC) get_proc("glReleaseShaderCompiler");
    gl3wShaderBinary = (PFNGLSHADERBINARYPROC) get_proc("glShaderBinary");
    gl3wGetShaderPrecisionFormat = (PFNGLGETSHADERPRECISIONFORMATPROC) get_proc("glGetShaderPrecisionFormat");
    gl3wDepthRangef = (PFNGLDEPTHRANGEFPROC) get_proc("glDepthRangef");
    gl3wClearDepthf = (PFNGLCLEARDEPTHFPROC) get_proc("glClearDepthf");
    gl3wGetProgramBinary = (PFNGLGETPROGRAMBINARYPROC) get_proc("glGetProgramBinary");
    gl3wProgramBinary = (PFNGLPROGRAMBINARYPROC) get_proc("glProgramBinary");
    gl3wProgramParameteri = (PFNGLPROGRAMPARAMETERIPROC) get_proc("glProgramParameteri");
    gl3wUseProgramStages = (PFNGLUSEPROGRAMSTAGESPROC) get_proc("glUseProgramStages");
    gl3wActiveShaderProgram = (PFNGLACTIVESHADERPROGRAMPROC) get_proc("glActiveShaderProgram");
    gl3wCreateShaderProgramv = (PFNGLCREATESHADERPROGRAMVPROC) get_proc("glCreateShaderProgramv");
    gl3wBindProgramPipeline = (PFNGLBINDPROGRAMPIPELINEPROC) get_proc("glBindProgramPipeline");
    gl3wDeleteProgramPipelines = (PFNGLDELETEPROGRAMPIPELINESPROC) get_proc("glDeleteProgramPipelines");
    gl3wGenProgramPipelines = (PFNGLGENPROGRAMPIPELINESPROC) get_proc("glGenProgramPipelines");
    gl3wIsProgramPipeline = (PFNGLISPROGRAMPIPELINEPROC) get_proc("glIsProgramPipeline");
    gl3wGetProgramPipelineiv = (PFNGLGETPROGRAMPIPELINEIVPROC) get_proc("glGetProgramPipelineiv");
    gl3wProgramUniform1i = (PFNGLPROGRAMUNIFORM1IPROC) get_proc("glProgramUniform1i");
    gl3wProgramUniform1iv = (PFNGLPROGRAMUNIFORM1IVPROC) get_proc("glProgramUniform1iv");
    gl3wProgramUniform1f = (PFNGLPROGRAMUNIFORM1FPROC) get_proc("glProgramUniform1f");
    gl3wProgramUniform1fv = (PFNGLPROGRAMUNIFORM1FVPROC) get_proc("glProgramUniform1fv");
    gl3wProgramUniform1d = (PFNGLPROGRAMUNIFORM1DPROC) get_proc("glProgramUniform1d");
    gl3wProgramUniform1dv = (PFNGLPROGRAMUNIFORM1DVPROC) get_proc("glProgramUniform1dv");
    gl3wProgramUniform1ui = (PFNGLPROGRAMUNIFORM1UIPROC) get_proc("glProgramUniform1ui");
    gl3wProgramUniform1uiv = (PFNGLPROGRAMUNIFORM1UIVPROC) get_proc("glProgramUniform1uiv");
    gl3wProgramUniform2i = (PFNGLPROGRAMUNIFORM2IPROC) get_proc("glProgramUniform2i");
    gl3wProgramUniform2iv = (PFNGLPROGRAMUNIFORM2IVPROC) get_proc("glProgramUniform2iv");
    gl3wProgramUniform2f = (PFNGLPROGRAMUNIFORM2FPROC) get_proc("glProgramUniform2f");
    gl3wProgramUniform2fv = (PFNGLPROGRAMUNIFORM2FVPROC) get_proc("glProgramUniform2fv");
    gl3wProgramUniform2d = (PFNGLPROGRAMUNIFORM2DPROC) get_proc("glProgramUniform2d");
    gl3wProgramUniform2dv = (PFNGLPROGRAMUNIFORM2DVPROC) get_proc("glProgramUniform2dv");
    gl3wProgramUniform2ui = (PFNGLPROGRAMUNIFORM2UIPROC) get_proc("glProgramUniform2ui");
    gl3wProgramUniform2uiv = (PFNGLPROGRAMUNIFORM2UIVPROC) get_proc("glProgramUniform2uiv");
    gl3wProgramUniform3i = (PFNGLPROGRAMUNIFORM3IPROC) get_proc("glProgramUniform3i");
    gl3wProgramUniform3iv = (PFNGLPROGRAMUNIFORM3IVPROC) get_proc("glProgramUniform3iv");
    gl3wProgramUniform3f = (PFNGLPROGRAMUNIFORM3FPROC) get_proc("glProgramUniform3f");
    gl3wProgramUniform3fv = (PFNGLPROGRAMUNIFORM3FVPROC) get_proc("glProgramUniform3fv");
    gl3wProgramUniform3d = (PFNGLPROGRAMUNIFORM3DPROC) get_proc("glProgramUniform3d");
    gl3wProgramUniform3dv = (PFNGLPROGRAMUNIFORM3DVPROC) get_proc("glProgramUniform3dv");
    gl3wProgramUniform3ui = (PFNGLPROGRAMUNIFORM3UIPROC) get_proc("glProgramUniform3ui");
    gl3wProgramUniform3uiv = (PFNGLPROGRAMUNIFORM3UIVPROC) get_proc("glProgramUniform3uiv");
    gl3wProgramUniform4i = (PFNGLPROGRAMUNIFORM4IPROC) get_proc("glProgramUniform4i");
    gl3wProgramUniform4iv = (PFNGLPROGRAMUNIFORM4IVPROC) get_proc("glProgramUniform4iv");
    gl3wProgramUniform4f = (PFNGLPROGRAMUNIFORM4FPROC) get_proc("glProgramUniform4f");
    gl3wProgramUniform4fv = (PFNGLPROGRAMUNIFORM4FVPROC) get_proc("glProgramUniform4fv");
    gl3wProgramUniform4d = (PFNGLPROGRAMUNIFORM4DPROC) get_proc("glProgramUniform4d");
    gl3wProgramUniform4dv = (PFNGLPROGRAMUNIFORM4DVPROC) get_proc("glProgramUniform4dv");
    gl3wProgramUniform4ui = (PFNGLPROGRAMUNIFORM4UIPROC) get_proc("glProgramUniform4ui");
    gl3wProgramUniform4uiv = (PFNGLPROGRAMUNIFORM4UIVPROC) get_proc("glProgramUniform4uiv");
    gl3wProgramUniformMatrix2fv = (PFNGLPROGRAMUNIFORMMATRIX2FVPROC) get_proc("glProgramUniformMatrix2fv");
    gl3wProgramUniformMatrix3fv = (PFNGLPROGRAMUNIFORMMATRIX3FVPROC) get_proc("glProgramUniformMatrix3fv");
    gl3wProgramUniformMatrix4fv = (PFNGLPROGRAMUNIFORMMATRIX4FVPROC) get_proc("glProgramUniformMatrix4fv");
    gl3wProgramUniformMatrix2dv = (PFNGLPROGRAMUNIFORMMATRIX2DVPROC) get_proc("glProgramUniformMatrix2dv");
    gl3wProgramUniformMatrix3dv = (PFNGLPROGRAMUNIFORMMATRIX3DVPROC) get_proc("glProgramUniformMatrix3dv");
    gl3wProgramUniformMatrix4dv = (PFNGLPROGRAMUNIFORMMATRIX4DVPROC) get_proc("glProgramUniformMatrix4dv");
    gl3wProgramUniformMatrix2x3fv = (PFNGLPROGRAMUNIFORMMATRIX2X3FVPROC) get_proc("glProgramUniformMatrix2x3fv");
    gl3wProgramUniformMatrix3x2fv = (PFNGLPROGRAMUNIFORMMATRIX3X2FVPROC) get_proc("glProgramUniformMatrix3x2fv");
    gl3wProgramUniformMatrix2x4fv = (PFNGLPROGRAMUNIFORMMATRIX2X4FVPROC) get_proc("glProgramUniformMatrix2x4fv");
    gl3wProgramUniformMatrix4x2fv = (PFNGLPROGRAMUNIFORMMATRIX4X2FVPROC) get_proc("glProgramUniformMatrix4x2fv");
    gl3wProgramUniformMatrix3x4fv = (PFNGLPROGRAMUNIFORMMATRIX3X4FVPROC) get_proc("glProgramUniformMatrix3x4fv");
    gl3wProgramUniformMatrix4x3fv = (PFNGLPROGRAMUNIFORMMATRIX4X3FVPROC) get_proc("glProgramUniformMatrix4x3fv");
    gl3wProgramUniformMatrix2x3dv = (PFNGLPROGRAMUNIFORMMATRIX2X3DVPROC) get_proc("glProgramUniformMatrix2x3dv");
    gl3wProgramUniformMatrix3x2dv = (PFNGLPROGRAMUNIFORMMATRIX3X2DVPROC) get_proc("glProgramUniformMatrix3x2dv");
    gl3wProgramUniformMatrix2x4dv = (PFNGLPROGRAMUNIFORMMATRIX2X4DVPROC) get_proc("glProgramUniformMatrix2x4dv");
    gl3wProgramUniformMatrix4x2dv = (PFNGLPROGRAMUNIFORMMATRIX4X2DVPROC) get_proc("glProgramUniformMatrix4x2dv");
    gl3wProgramUniformMatrix3x4dv = (PFNGLPROGRAMUNIFORMMATRIX3X4DVPROC) get_proc("glProgramUniformMatrix3x4dv");
    gl3wProgramUniformMatrix4x3dv = (PFNGLPROGRAMUNIFORMMATRIX4X3DVPROC) get_proc("glProgramUniformMatrix4x3dv");
    gl3wValidateProgramPipeline = (PFNGLVALIDATEPROGRAMPIPELINEPROC) get_proc("glValidateProgramPipeline");
    gl3wGetProgramPipelineInfoLog = (PFNGLGETPROGRAMPIPELINEINFOLOGPROC) get_proc("glGetProgramPipelineInfoLog");
    gl3wVertexAttribL1d = (PFNGLVERTEXATTRIBL1DPROC) get_proc("glVertexAttribL1d");
    gl3wVertexAttribL2d = (PFNGLVERTEXATTRIBL2DPROC) get_proc("glVertexAttribL2d");
    gl3wVertexAttribL3d = (PFNGLVERTEXATTRIBL3DPROC) get_proc("glVertexAttribL3d");
    gl3wVertexAttribL4d = (PFNGLVERTEXATTRIBL4DPROC) get_proc("glVertexAttribL4d");
    gl3wVertexAttribL1dv = (PFNGLVERTEXATTRIBL1DVPROC) get_proc("glVertexAttribL1dv");
    gl3wVertexAttribL2dv = (PFNGLVERTEXATTRIBL2DVPROC) get_proc("glVertexAttribL2dv");
    gl3wVertexAttribL3dv = (PFNGLVERTEXATTRIBL3DVPROC) get_proc("glVertexAttribL3dv");
    gl3wVertexAttribL4dv = (PFNGLVERTEXATTRIBL4DVPROC) get_proc("glVertexAttribL4dv");
    gl3wVertexAttribLPointer = (PFNGLVERTEXATTRIBLPOINTERPROC) get_proc("glVertexAttribLPointer");
    gl3wGetVertexAttribLdv = (PFNGLGETVERTEXATTRIBLDVPROC) get_proc("glGetVertexAttribLdv");
    gl3wViewportArrayv = (PFNGLVIEWPORTARRAYVPROC) get_proc("glViewportArrayv");
    gl3wViewportIndexedf = (PFNGLVIEWPORTINDEXEDFPROC) get_proc("glViewportIndexedf");
    gl3wViewportIndexedfv = (PFNGLVIEWPORTINDEXEDFVPROC) get_proc("glViewportIndexedfv");
    gl3wScissorArrayv = (PFNGLSCISSORARRAYVPROC) get_proc("glScissorArrayv");
    gl3wScissorIndexed = (PFNGLSCISSORINDEXEDPROC) get_proc("glScissorIndexed");
    gl3wScissorIndexedv = (PFNGLSCISSORINDEXEDVPROC) get_proc("glScissorIndexedv");
    gl3wDepthRangeArrayv = (PFNGLDEPTHRANGEARRAYVPROC) get_proc("glDepthRangeArrayv");
    gl3wDepthRangeIndexed = (PFNGLDEPTHRANGEINDEXEDPROC) get_proc("glDepthRangeIndexed");
    gl3wGetFloati_v = (PFNGLGETFLOATI_VPROC) get_proc("glGetFloati_v");
    gl3wGetDoublei_v = (PFNGLGETDOUBLEI_VPROC) get_proc("glGetDoublei_v");
    gl3wCreateSyncFromCLeventARB = (PFNGLCREATESYNCFROMCLEVENTARBPROC) get_proc("glCreateSyncFromCLeventARB");
    gl3wDebugMessageControlARB = (PFNGLDEBUGMESSAGECONTROLARBPROC) get_proc("glDebugMessageControlARB");
    gl3wDebugMessageInsertARB = (PFNGLDEBUGMESSAGEINSERTARBPROC) get_proc("glDebugMessageInsertARB");
    gl3wDebugMessageCallbackARB = (PFNGLDEBUGMESSAGECALLBACKARBPROC) get_proc("glDebugMessageCallbackARB");
    gl3wGetDebugMessageLogARB = (PFNGLGETDEBUGMESSAGELOGARBPROC) get_proc("glGetDebugMessageLogARB");
    gl3wGetGraphicsResetStatusARB = (PFNGLGETGRAPHICSRESETSTATUSARBPROC) get_proc("glGetGraphicsResetStatusARB");
    gl3wGetnTexImageARB = (PFNGLGETNTEXIMAGEARBPROC) get_proc("glGetnTexImageARB");
    gl3wReadnPixelsARB = (PFNGLREADNPIXELSARBPROC) get_proc("glReadnPixelsARB");
    gl3wGetnCompressedTexImageARB = (PFNGLGETNCOMPRESSEDTEXIMAGEARBPROC) get_proc("glGetnCompressedTexImageARB");
    gl3wGetnUniformfvARB = (PFNGLGETNUNIFORMFVARBPROC) get_proc("glGetnUniformfvARB");
    gl3wGetnUniformivARB = (PFNGLGETNUNIFORMIVARBPROC) get_proc("glGetnUniformivARB");
    gl3wGetnUniformuivARB = (PFNGLGETNUNIFORMUIVARBPROC) get_proc("glGetnUniformuivARB");
    gl3wGetnUniformdvARB = (PFNGLGETNUNIFORMDVARBPROC) get_proc("glGetnUniformdvARB");
    gl3wDrawArraysInstancedBaseInstance = (PFNGLDRAWARRAYSINSTANCEDBASEINSTANCEPROC) get_proc("glDrawArraysInstancedBaseInstance");
    gl3wDrawElementsInstancedBaseInstance = (PFNGLDRAWELEMENTSINSTANCEDBASEINSTANCEPROC) get_proc("glDrawElementsInstancedBaseInstance");
    gl3wDrawElementsInstancedBaseVertexBaseInstance = (PFNGLDRAWELEMENTSINSTANCEDBASEVERTEXBASEINSTANCEPROC) get_proc("glDrawElementsInstancedBaseVertexBaseInstance");
    gl3wDrawTransformFeedbackInstanced = (PFNGLDRAWTRANSFORMFEEDBACKINSTANCEDPROC) get_proc("glDrawTransformFeedbackInstanced");
    gl3wDrawTransformFeedbackStreamInstanced = (PFNGLDRAWTRANSFORMFEEDBACKSTREAMINSTANCEDPROC) get_proc("glDrawTransformFeedbackStreamInstanced");
    gl3wGetInternalformativ = (PFNGLGETINTERNALFORMATIVPROC) get_proc("glGetInternalformativ");
    gl3wGetActiveAtomicCounterBufferiv = (PFNGLGETACTIVEATOMICCOUNTERBUFFERIVPROC) get_proc("glGetActiveAtomicCounterBufferiv");
    gl3wBindImageTexture = (PFNGLBINDIMAGETEXTUREPROC) get_proc("glBindImageTexture");
    gl3wMemoryBarrier = (PFNGLMEMORYBARRIERPROC) get_proc("glMemoryBarrier");
    gl3wTexStorage1D = (PFNGLTEXSTORAGE1DPROC) get_proc("glTexStorage1D");
    gl3wTexStorage2D = (PFNGLTEXSTORAGE2DPROC) get_proc("glTexStorage2D");
    gl3wTexStorage3D = (PFNGLTEXSTORAGE3DPROC) get_proc("glTexStorage3D");
    gl3wTextureStorage1DEXT = (PFNGLTEXTURESTORAGE1DEXTPROC) get_proc("glTextureStorage1DEXT");
    gl3wTextureStorage2DEXT = (PFNGLTEXTURESTORAGE2DEXTPROC) get_proc("glTextureStorage2DEXT");
    gl3wTextureStorage3DEXT = (PFNGLTEXTURESTORAGE3DEXTPROC) get_proc("glTextureStorage3DEXT");
    gl3wDebugMessageControl = (PFNGLDEBUGMESSAGECONTROLPROC) get_proc("glDebugMessageControl");
    gl3wDebugMessageInsert = (PFNGLDEBUGMESSAGEINSERTPROC) get_proc("glDebugMessageInsert");
    gl3wDebugMessageCallback = (PFNGLDEBUGMESSAGECALLBACKPROC) get_proc("glDebugMessageCallback");
    gl3wGetDebugMessageLog = (PFNGLGETDEBUGMESSAGELOGPROC) get_proc("glGetDebugMessageLog");
    gl3wPushDebugGroup = (PFNGLPUSHDEBUGGROUPPROC) get_proc("glPushDebugGroup");
    gl3wPopDebugGroup = (PFNGLPOPDEBUGGROUPPROC) get_proc("glPopDebugGroup");
    gl3wObjectLabel = (PFNGLOBJECTLABELPROC) get_proc("glObjectLabel");
    gl3wGetObjectLabel = (PFNGLGETOBJECTLABELPROC) get_proc("glGetObjectLabel");
    gl3wObjectPtrLabel = (PFNGLOBJECTPTRLABELPROC) get_proc("glObjectPtrLabel");
    gl3wGetObjectPtrLabel = (PFNGLGETOBJECTPTRLABELPROC) get_proc("glGetObjectPtrLabel");
    gl3wClearBufferData = (PFNGLCLEARBUFFERDATAPROC) get_proc("glClearBufferData");
    gl3wClearBufferSubData = (PFNGLCLEARBUFFERSUBDATAPROC) get_proc("glClearBufferSubData");
    gl3wClearNamedBufferDataEXT = (PFNGLCLEARNAMEDBUFFERDATAEXTPROC) get_proc("glClearNamedBufferDataEXT");
    gl3wClearNamedBufferSubDataEXT = (PFNGLCLEARNAMEDBUFFERSUBDATAEXTPROC) get_proc("glClearNamedBufferSubDataEXT");
    gl3wDispatchCompute = (PFNGLDISPATCHCOMPUTEPROC) get_proc("glDispatchCompute");
    gl3wDispatchComputeIndirect = (PFNGLDISPATCHCOMPUTEINDIRECTPROC) get_proc("glDispatchComputeIndirect");
    gl3wCopyImageSubData = (PFNGLCOPYIMAGESUBDATAPROC) get_proc("glCopyImageSubData");
    gl3wTextureView = (PFNGLTEXTUREVIEWPROC) get_proc("glTextureView");
    gl3wBindVertexBuffer = (PFNGLBINDVERTEXBUFFERPROC) get_proc("glBindVertexBuffer");
    gl3wVertexAttribFormat = (PFNGLVERTEXATTRIBFORMATPROC) get_proc("glVertexAttribFormat");
    gl3wVertexAttribIFormat = (PFNGLVERTEXATTRIBIFORMATPROC) get_proc("glVertexAttribIFormat");
    gl3wVertexAttribLFormat = (PFNGLVERTEXATTRIBLFORMATPROC) get_proc("glVertexAttribLFormat");
    gl3wVertexAttribBinding = (PFNGLVERTEXATTRIBBINDINGPROC) get_proc("glVertexAttribBinding");
    gl3wVertexBindingDivisor = (PFNGLVERTEXBINDINGDIVISORPROC) get_proc("glVertexBindingDivisor");
    gl3wVertexArrayBindVertexBufferEXT = (PFNGLVERTEXARRAYBINDVERTEXBUFFEREXTPROC) get_proc("glVertexArrayBindVertexBufferEXT");
    gl3wVertexArrayVertexAttribFormatEXT = (PFNGLVERTEXARRAYVERTEXATTRIBFORMATEXTPROC) get_proc("glVertexArrayVertexAttribFormatEXT");
    gl3wVertexArrayVertexAttribIFormatEXT = (PFNGLVERTEXARRAYVERTEXATTRIBIFORMATEXTPROC) get_proc("glVertexArrayVertexAttribIFormatEXT");
    gl3wVertexArrayVertexAttribLFormatEXT = (PFNGLVERTEXARRAYVERTEXATTRIBLFORMATEXTPROC) get_proc("glVertexArrayVertexAttribLFormatEXT");
    gl3wVertexArrayVertexAttribBindingEXT = (PFNGLVERTEXARRAYVERTEXATTRIBBINDINGEXTPROC) get_proc("glVertexArrayVertexAttribBindingEXT");
    gl3wVertexArrayVertexBindingDivisorEXT = (PFNGLVERTEXARRAYVERTEXBINDINGDIVISOREXTPROC) get_proc("glVertexArrayVertexBindingDivisorEXT");
    gl3wFramebufferParameteri = (PFNGLFRAMEBUFFERPARAMETERIPROC) get_proc("glFramebufferParameteri");
    gl3wGetFramebufferParameteriv = (PFNGLGETFRAMEBUFFERPARAMETERIVPROC) get_proc("glGetFramebufferParameteriv");
    gl3wNamedFramebufferParameteriEXT = (PFNGLNAMEDFRAMEBUFFERPARAMETERIEXTPROC) get_proc("glNamedFramebufferParameteriEXT");
    gl3wGetNamedFramebufferParameterivEXT = (PFNGLGETNAMEDFRAMEBUFFERPARAMETERIVEXTPROC) get_proc("glGetNamedFramebufferParameterivEXT");
    gl3wGetInternalformati64v = (PFNGLGETINTERNALFORMATI64VPROC) get_proc("glGetInternalformati64v");
    gl3wInvalidateTexSubImage = (PFNGLINVALIDATETEXSUBIMAGEPROC) get_proc("glInvalidateTexSubImage");
    gl3wInvalidateTexImage = (PFNGLINVALIDATETEXIMAGEPROC) get_proc("glInvalidateTexImage");
    gl3wInvalidateBufferSubData = (PFNGLINVALIDATEBUFFERSUBDATAPROC) get_proc("glInvalidateBufferSubData");
    gl3wInvalidateBufferData = (PFNGLINVALIDATEBUFFERDATAPROC) get_proc("glInvalidateBufferData");
    gl3wInvalidateFramebuffer = (PFNGLINVALIDATEFRAMEBUFFERPROC) get_proc("glInvalidateFramebuffer");
    gl3wInvalidateSubFramebuffer = (PFNGLINVALIDATESUBFRAMEBUFFERPROC) get_proc("glInvalidateSubFramebuffer");
    gl3wMultiDrawArraysIndirect = (PFNGLMULTIDRAWARRAYSINDIRECTPROC) get_proc("glMultiDrawArraysIndirect");
    gl3wMultiDrawElementsIndirect = (PFNGLMULTIDRAWELEMENTSINDIRECTPROC) get_proc("glMultiDrawElementsIndirect");
    gl3wGetProgramInterfaceiv = (PFNGLGETPROGRAMINTERFACEIVPROC) get_proc("glGetProgramInterfaceiv");
    gl3wGetProgramResourceIndex = (PFNGLGETPROGRAMRESOURCEINDEXPROC) get_proc("glGetProgramResourceIndex");
    gl3wGetProgramResourceName = (PFNGLGETPROGRAMRESOURCENAMEPROC) get_proc("glGetProgramResourceName");
    gl3wGetProgramResourceiv = (PFNGLGETPROGRAMRESOURCEIVPROC) get_proc("glGetProgramResourceiv");
    gl3wGetProgramResourceLocation = (PFNGLGETPROGRAMRESOURCELOCATIONPROC) get_proc("glGetProgramResourceLocation");
    gl3wGetProgramResourceLocationIndex = (PFNGLGETPROGRAMRESOURCELOCATIONINDEXPROC) get_proc("glGetProgramResourceLocationIndex");
    gl3wShaderStorageBlockBinding = (PFNGLSHADERSTORAGEBLOCKBINDINGPROC) get_proc("glShaderStorageBlockBinding");
    gl3wTexBufferRange = (PFNGLTEXBUFFERRANGEPROC) get_proc("glTexBufferRange");
    gl3wTextureBufferRangeEXT = (PFNGLTEXTUREBUFFERRANGEEXTPROC) get_proc("glTextureBufferRangeEXT");
    gl3wTexStorage2DMultisample = (PFNGLTEXSTORAGE2DMULTISAMPLEPROC) get_proc("glTexStorage2DMultisample");
    gl3wTexStorage3DMultisample = (PFNGLTEXSTORAGE3DMULTISAMPLEPROC) get_proc("glTexStorage3DMultisample");
    gl3wTextureStorage2DMultisampleEXT = (PFNGLTEXTURESTORAGE2DMULTISAMPLEEXTPROC) get_proc("glTextureStorage2DMultisampleEXT");
    gl3wTextureStorage3DMultisampleEXT = (PFNGLTEXTURESTORAGE3DMULTISAMPLEEXTPROC) get_proc("glTextureStorage3DMultisampleEXT");
}
