//
//  AppDelegate.m
//  LibChucKTest
//
//  Created by Spencer Salazar on 2/27/15.
//  Copyright (c) 2015 Spencer Salazar. All rights reserved.
//

#import "AppDelegate.h"
#import "TheAmazingAudioEngine.h"
#import <AVFoundation/AVFoundation.h>

#include "libchuck.h"


@interface AppDelegate ()
{
    BOOL _iaaConnected;
    BOOL _audioActive;
}

@property (strong, nonatomic) AEAudioController *audioController;

- (void)audioUnitPropertyChanged:(void *)object unit:(AudioUnit)unit
                          propID:(AudioUnitPropertyID)propID scope:(AudioUnitScope)scope
                         element:(AudioUnitElement)element;

@end


void AudioUnitPropertyChanged(void *inRefCon, AudioUnit inUnit,
                              AudioUnitPropertyID inID, AudioUnitScope inScope,
                              AudioUnitElement inElement)
{
    AppDelegate *_self = (__bridge AppDelegate *)inRefCon;
    [_self audioUnitPropertyChanged:inRefCon unit:inUnit propID:inID
                              scope:inScope element:inElement];
}


@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    
    _iaaConnected = NO;
    
    chuck_options options;
    options.sample_rate = 44100;
#if defined(TARGET_IPHONE_SIMULATOR)
    options.buffer_size = 512;
#elif defined(TARGET_OS_IPHONE)
    options.buffer_size = 512;
#endif
    options.num_channels = 2;
    options.slave = true;
    
    chuck_inst *ck = libchuck_create(&options);
    
    libchuck_vm_start(ck);
    
    AudioStreamBasicDescription audioDescription;
    memset(&audioDescription, 0, sizeof(audioDescription));
    audioDescription.mFormatID          = kAudioFormatLinearPCM;
    audioDescription.mFormatFlags       = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    audioDescription.mChannelsPerFrame  = options.num_channels;
    audioDescription.mBytesPerPacket    = sizeof(float);
    audioDescription.mFramesPerPacket   = 1;
    audioDescription.mBytesPerFrame     = sizeof(float);
    audioDescription.mBitsPerChannel    = 8 * sizeof(float);
    audioDescription.mSampleRate        = options.sample_rate;

    self.audioController = [[AEAudioController alloc] initWithAudioDescription:audioDescription inputEnabled:NO];
    _audioController.preferredBufferDuration = 0.005;
    
    [_audioController addChannels:@[[AEBlockChannel channelWithBlock:^(const AudioTimeStamp *time,
                                                                       UInt32 frames,
                                                                       AudioBufferList *audio) {
        float input[512];
        float output[512];
        
        libchuck_slave_process(ck, input, output, frames);
        
        // deinterleave
        for(int i = 0; i < frames; i++)
        {
            ((float*)(audio->mBuffers[0].mData))[i] = output[i*2];
            ((float*)(audio->mBuffers[1].mData))[i] = output[i*2+1];
        }
    }]]];
    
    // setup inter-app audio
    AudioComponentDescription desc = {
        kAudioUnitType_RemoteGenerator, 'iasp', 'SLZR', 0, 0
    };
    AudioOutputUnitPublish(&desc, CFSTR("ChucK Test"), 1, _audioController.audioUnit);
    
    AudioUnitAddPropertyListener(_audioController.audioUnit,
                                 kAudioUnitProperty_IsInterAppConnected,
                                 AudioUnitPropertyChanged,
                                 (__bridge void *) self);
    
    [_audioController start:NULL];
    _audioActive = YES;

    libchuck_add_shred(ck, "", "SinOsc s => dac; 1::week => now;");
    
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    
    NSLog(@"applicationWillResignActive:");
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    
    if(!_iaaConnected)
    {
        if(_audioActive)
        {
            [self.audioController stop];
            _audioActive = NO;
        }
    }
    
    NSLog(@"applicationDidEnterBackground:");
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    if(!_audioActive)
    {
        [self.audioController start:NULL];
        _audioActive = YES;
    }
    
    NSLog(@"applicationWillEnterForeground:");
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    NSLog(@"applicationDidBecomeActive:");
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    [self.audioController stop];
    self.audioController = nil;
}

- (void)audioUnitPropertyChanged:(void *)object unit:(AudioUnit)unit
                          propID:(AudioUnitPropertyID)propID
                           scope:(AudioUnitScope)scope
                         element:(AudioUnitElement)element
{
    if(propID == kAudioUnitProperty_IsInterAppConnected)
    {
        NSLog(@"audioUnitPropertyChanged: kAudioUnitProperty_IsInterAppConnected");
        
        UInt32 connected;
        UInt32 dataSize = sizeof(UInt32);
        AudioUnitGetProperty(unit,
                             kAudioUnitProperty_IsInterAppConnected,
                             kAudioUnitScope_Global,
                             0, &connected, &dataSize);
        _iaaConnected = (BOOL)connected;
        
        if(_iaaConnected)
        {
            if(!_audioActive)
            {
                [self.audioController start:NULL];
                _audioActive = YES;
            }
        }
        else
        {
            if(_audioActive)
            {
                [self.audioController stop];
                _audioActive = NO;
            }
        }
    }
}

@end
