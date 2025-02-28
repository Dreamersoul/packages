// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:async/async.dart';
import 'package:camera_android_camerax/camera_android_camerax.dart';
import 'package:camera_android_camerax/src/analyzer.dart';
import 'package:camera_android_camerax/src/camera.dart';
import 'package:camera_android_camerax/src/camera_info.dart';
import 'package:camera_android_camerax/src/camera_selector.dart';
import 'package:camera_android_camerax/src/camerax_library.g.dart';
import 'package:camera_android_camerax/src/exposure_state.dart';
import 'package:camera_android_camerax/src/image_analysis.dart';
import 'package:camera_android_camerax/src/image_capture.dart';
import 'package:camera_android_camerax/src/image_proxy.dart';
import 'package:camera_android_camerax/src/plane_proxy.dart';
import 'package:camera_android_camerax/src/preview.dart';
import 'package:camera_android_camerax/src/process_camera_provider.dart';
import 'package:camera_android_camerax/src/system_services.dart';
import 'package:camera_android_camerax/src/use_case.dart';
import 'package:camera_android_camerax/src/zoom_state.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart' show DeviceOrientation, Uint8List;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'android_camera_camerax_test.mocks.dart';
import 'test_camerax_library.g.dart';

@GenerateNiceMocks(<MockSpec<Object>>[
  MockSpec<Camera>(),
  MockSpec<CameraInfo>(),
  MockSpec<CameraImageData>(),
  MockSpec<CameraSelector>(),
  MockSpec<ExposureState>(),
  MockSpec<ImageAnalysis>(),
  MockSpec<ImageCapture>(),
  MockSpec<ImageProxy>(),
  MockSpec<PlaneProxy>(),
  MockSpec<Preview>(),
  MockSpec<ProcessCameraProvider>(),
  MockSpec<TestInstanceManagerHostApi>(),
  MockSpec<ZoomState>(),
])
@GenerateMocks(<Type>[BuildContext])
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mocks the call to clear the native InstanceManager.
  TestInstanceManagerHostApi.setup(MockTestInstanceManagerHostApi());

  test('Should fetch CameraDescription instances for available cameras',
      () async {
    // Arrange
    final MockAndroidCameraCameraX camera = MockAndroidCameraCameraX();
    camera.processCameraProvider = MockProcessCameraProvider();
    final List<dynamic> returnData = <dynamic>[
      <String, dynamic>{
        'name': 'Camera 0',
        'lensFacing': 'back',
        'sensorOrientation': 0
      },
      <String, dynamic>{
        'name': 'Camera 1',
        'lensFacing': 'front',
        'sensorOrientation': 90
      }
    ];

    // Create mocks to use
    final MockCameraInfo mockFrontCameraInfo = MockCameraInfo();
    final MockCameraInfo mockBackCameraInfo = MockCameraInfo();

    // Mock calls to native platform
    when(camera.processCameraProvider!.getAvailableCameraInfos()).thenAnswer(
        (_) async => <MockCameraInfo>[mockBackCameraInfo, mockFrontCameraInfo]);
    when(camera.mockBackCameraSelector
            .filter(<MockCameraInfo>[mockFrontCameraInfo]))
        .thenAnswer((_) async => <MockCameraInfo>[]);
    when(camera.mockBackCameraSelector
            .filter(<MockCameraInfo>[mockBackCameraInfo]))
        .thenAnswer((_) async => <MockCameraInfo>[mockBackCameraInfo]);
    when(camera.mockFrontCameraSelector
            .filter(<MockCameraInfo>[mockBackCameraInfo]))
        .thenAnswer((_) async => <MockCameraInfo>[]);
    when(camera.mockFrontCameraSelector
            .filter(<MockCameraInfo>[mockFrontCameraInfo]))
        .thenAnswer((_) async => <MockCameraInfo>[mockFrontCameraInfo]);
    when(mockBackCameraInfo.getSensorRotationDegrees())
        .thenAnswer((_) async => 0);
    when(mockFrontCameraInfo.getSensorRotationDegrees())
        .thenAnswer((_) async => 90);

    final List<CameraDescription> cameraDescriptions =
        await camera.availableCameras();

    expect(cameraDescriptions.length, returnData.length);
    for (int i = 0; i < returnData.length; i++) {
      final Map<String, Object?> typedData =
          (returnData[i] as Map<dynamic, dynamic>).cast<String, Object?>();
      final CameraDescription cameraDescription = CameraDescription(
        name: typedData['name']! as String,
        lensDirection: (typedData['lensFacing']! as String) == 'front'
            ? CameraLensDirection.front
            : CameraLensDirection.back,
        sensorOrientation: typedData['sensorOrientation']! as int,
      );
      expect(cameraDescriptions[i], cameraDescription);
    }
  });

  test(
      'createCamera requests permissions, starts listening for device orientation changes, and returns flutter surface texture ID',
      () async {
    final MockAndroidCameraCameraX camera = MockAndroidCameraCameraX();
    final MockProcessCameraProvider mockProcessCameraProvider =
        MockProcessCameraProvider();
    final MockCamera mockCamera = MockCamera();
    const CameraLensDirection testLensDirection = CameraLensDirection.back;
    const int testSensorOrientation = 90;
    const CameraDescription testCameraDescription = CameraDescription(
        name: 'cameraName',
        lensDirection: testLensDirection,
        sensorOrientation: testSensorOrientation);
    const ResolutionPreset testResolutionPreset = ResolutionPreset.veryHigh;
    const bool enableAudio = true;
    const int testSurfaceTextureId = 6;

    camera.processCameraProvider = mockProcessCameraProvider;

    when(camera.testPreview.setSurfaceProvider())
        .thenAnswer((_) async => testSurfaceTextureId);
    when(mockProcessCameraProvider.bindToLifecycle(any, any))
        .thenAnswer((_) => Future<Camera>.value(mockCamera));
    when(mockCamera.getCameraInfo())
        .thenAnswer((_) => Future<CameraInfo>.value(MockCameraInfo()));

    expect(
        await camera.createCamera(testCameraDescription, testResolutionPreset,
            enableAudio: enableAudio),
        equals(testSurfaceTextureId));

    // Verify permissions are requested and the camera starts listening for device orientation changes.
    expect(camera.cameraPermissionsRequested, isTrue);
    expect(camera.startedListeningForDeviceOrientationChanges, isTrue);

    // Verify CameraSelector is set with appropriate lens direction.
    expect(camera.cameraSelector, equals(camera.mockBackCameraSelector));

    // Verify the camera's Preview instance is instantiated properly.
    expect(camera.preview, equals(camera.testPreview));

    // Verify the camera's ImageCapture instance is instantiated properly.
    expect(camera.imageCapture, equals(camera.testImageCapture));

    // Verify the camera's Preview instance has its surface provider set.
    verify(camera.preview!.setSurfaceProvider());
  });

  test(
      'createCamera binds Preview and ImageCapture use cases to ProcessCameraProvider instance',
      () async {
    final MockAndroidCameraCameraX camera = MockAndroidCameraCameraX();
    final MockProcessCameraProvider mockProcessCameraProvider =
        MockProcessCameraProvider();
    final MockCamera mockCamera = MockCamera();
    final MockCameraInfo mockCameraInfo = MockCameraInfo();
    const CameraLensDirection testLensDirection = CameraLensDirection.back;
    const int testSensorOrientation = 90;
    const CameraDescription testCameraDescription = CameraDescription(
        name: 'cameraName',
        lensDirection: testLensDirection,
        sensorOrientation: testSensorOrientation);
    const ResolutionPreset testResolutionPreset = ResolutionPreset.veryHigh;
    const bool enableAudio = true;

    camera.processCameraProvider = mockProcessCameraProvider;

    when(mockProcessCameraProvider.bindToLifecycle(
            camera.mockBackCameraSelector,
            <UseCase>[camera.testPreview, camera.testImageCapture]))
        .thenAnswer((_) => Future<Camera>.value(mockCamera));
    when(mockCamera.getCameraInfo())
        .thenAnswer((_) => Future<CameraInfo>.value(mockCameraInfo));

    await camera.createCamera(testCameraDescription, testResolutionPreset,
        enableAudio: enableAudio);

    // Verify expected UseCases were bound.
    verify(camera.processCameraProvider!.bindToLifecycle(camera.cameraSelector!,
        <UseCase>[camera.testPreview, camera.testImageCapture]));

    // Verify the camera's CameraInfo instance got updated.
    expect(camera.cameraInfo, equals(mockCameraInfo));
  });

  test(
      'initializeCamera throws a CameraException when createCamera has not been called before initializedCamera',
      () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    expect(() => camera.initializeCamera(3), throwsA(isA<CameraException>()));
  });

  test('initializeCamera sends expected CameraInitializedEvent', () async {
    final MockAndroidCameraCameraX camera = MockAndroidCameraCameraX();
    final MockProcessCameraProvider mockProcessCameraProvider =
        MockProcessCameraProvider();
    const int cameraId = 10;
    const CameraLensDirection testLensDirection = CameraLensDirection.back;
    const int testSensorOrientation = 90;
    const CameraDescription testCameraDescription = CameraDescription(
        name: 'cameraName',
        lensDirection: testLensDirection,
        sensorOrientation: testSensorOrientation);
    const ResolutionPreset testResolutionPreset = ResolutionPreset.veryHigh;
    const bool enableAudio = true;
    const int resolutionWidth = 350;
    const int resolutionHeight = 750;
    final Camera mockCamera = MockCamera();
    final ResolutionInfo testResolutionInfo =
        ResolutionInfo(width: resolutionWidth, height: resolutionHeight);

    // TODO(camsim99): Modify this when camera configuration is supported and
    // defualt values no longer being used.
    // https://github.com/flutter/flutter/issues/120468
    // https://github.com/flutter/flutter/issues/120467
    final CameraInitializedEvent testCameraInitializedEvent =
        CameraInitializedEvent(
            cameraId,
            resolutionWidth.toDouble(),
            resolutionHeight.toDouble(),
            ExposureMode.auto,
            false,
            FocusMode.auto,
            false);

    camera.processCameraProvider = mockProcessCameraProvider;

    // Call createCamera.
    when(camera.testPreview.setSurfaceProvider())
        .thenAnswer((_) async => cameraId);

    when(mockProcessCameraProvider.bindToLifecycle(any, any))
        .thenAnswer((_) async => mockCamera);
    when(mockCamera.getCameraInfo())
        .thenAnswer((_) => Future<CameraInfo>.value(MockCameraInfo()));
    when(camera.testPreview.getResolutionInfo())
        .thenAnswer((_) async => testResolutionInfo);

    await camera.createCamera(testCameraDescription, testResolutionPreset,
        enableAudio: enableAudio);

    // Start listening to camera events stream to verify the proper CameraInitializedEvent is sent.
    camera.cameraEventStreamController.stream.listen((CameraEvent event) {
      expect(event, const TypeMatcher<CameraInitializedEvent>());
      expect(event, equals(testCameraInitializedEvent));
    });

    await camera.initializeCamera(cameraId);

    // Check camera instance was received.
    expect(camera.camera, isNotNull);
  });

  test('dispose releases Flutter surface texture and unbinds all use cases',
      () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();

    camera.preview = MockPreview();
    camera.processCameraProvider = MockProcessCameraProvider();

    camera.dispose(3);

    verify(camera.preview!.releaseFlutterSurfaceTexture());
    verify(camera.processCameraProvider!.unbindAll());
  });

  test('onCameraInitialized stream emits CameraInitializedEvents', () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    const int cameraId = 16;
    final Stream<CameraInitializedEvent> eventStream =
        camera.onCameraInitialized(cameraId);
    final StreamQueue<CameraInitializedEvent> streamQueue =
        StreamQueue<CameraInitializedEvent>(eventStream);
    const CameraInitializedEvent testEvent = CameraInitializedEvent(
        cameraId, 320, 80, ExposureMode.auto, false, FocusMode.auto, false);

    camera.cameraEventStreamController.add(testEvent);

    expect(await streamQueue.next, testEvent);
    await streamQueue.cancel();
  });

  test('onCameraError stream emits errors caught by system services', () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    const int cameraId = 27;
    const String testErrorDescription = 'Test error description!';
    final Stream<CameraErrorEvent> eventStream = camera.onCameraError(cameraId);
    final StreamQueue<CameraErrorEvent> streamQueue =
        StreamQueue<CameraErrorEvent>(eventStream);

    SystemServices.cameraErrorStreamController.add(testErrorDescription);

    expect(await streamQueue.next,
        equals(const CameraErrorEvent(cameraId, testErrorDescription)));
    await streamQueue.cancel();
  });

  test(
      'onDeviceOrientationChanged stream emits changes in device oreintation detected by system services',
      () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    final Stream<DeviceOrientationChangedEvent> eventStream =
        camera.onDeviceOrientationChanged();
    final StreamQueue<DeviceOrientationChangedEvent> streamQueue =
        StreamQueue<DeviceOrientationChangedEvent>(eventStream);
    const DeviceOrientationChangedEvent testEvent =
        DeviceOrientationChangedEvent(DeviceOrientation.portraitDown);

    SystemServices.deviceOrientationChangedStreamController.add(testEvent);

    expect(await streamQueue.next, testEvent);
    await streamQueue.cancel();
  });

  test(
      'pausePreview unbinds preview from lifecycle when preview is nonnull and has been bound to lifecycle',
      () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();

    camera.processCameraProvider = MockProcessCameraProvider();
    camera.preview = MockPreview();

    when(camera.processCameraProvider!.isBound(camera.preview!))
        .thenAnswer((_) async => true);

    await camera.pausePreview(579);

    verify(camera.processCameraProvider!.unbind(<UseCase>[camera.preview!]));
  });

  test(
      'pausePreview does not unbind preview from lifecycle when preview has not been bound to lifecycle',
      () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();

    camera.processCameraProvider = MockProcessCameraProvider();
    camera.preview = MockPreview();

    await camera.pausePreview(632);

    verifyNever(
        camera.processCameraProvider!.unbind(<UseCase>[camera.preview!]));
  });

  test('resumePreview does not bind preview to lifecycle if already bound',
      () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    final MockProcessCameraProvider mockProcessCameraProvider =
        MockProcessCameraProvider();
    final MockCamera mockCamera = MockCamera();
    final MockCameraInfo mockCameraInfo = MockCameraInfo();

    camera.processCameraProvider = mockProcessCameraProvider;
    camera.cameraSelector = MockCameraSelector();
    camera.preview = MockPreview();

    when(camera.processCameraProvider!.isBound(camera.preview!))
        .thenAnswer((_) async => true);

    when(mockProcessCameraProvider.bindToLifecycle(any, any))
        .thenAnswer((_) => Future<Camera>.value(mockCamera));
    when(mockCamera.getCameraInfo())
        .thenAnswer((_) => Future<CameraInfo>.value(mockCameraInfo));

    await camera.resumePreview(78);

    verifyNever(camera.processCameraProvider!
        .bindToLifecycle(camera.cameraSelector!, <UseCase>[camera.preview!]));
    expect(camera.cameraInfo, isNot(mockCameraInfo));
  });

  test('resumePreview binds preview to lifecycle if not already bound',
      () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    final MockProcessCameraProvider mockProcessCameraProvider =
        MockProcessCameraProvider();
    final MockCamera mockCamera = MockCamera();
    final MockCameraInfo mockCameraInfo = MockCameraInfo();

    camera.processCameraProvider = mockProcessCameraProvider;
    camera.cameraSelector = MockCameraSelector();
    camera.preview = MockPreview();

    when(mockProcessCameraProvider.bindToLifecycle(any, any))
        .thenAnswer((_) => Future<Camera>.value(mockCamera));
    when(mockCamera.getCameraInfo())
        .thenAnswer((_) => Future<CameraInfo>.value(mockCameraInfo));

    await camera.resumePreview(78);

    verify(camera.processCameraProvider!
        .bindToLifecycle(camera.cameraSelector!, <UseCase>[camera.preview!]));
    expect(camera.cameraInfo, equals(mockCameraInfo));
  });

  test(
      'buildPreview returns a FutureBuilder that does not return a Texture until the preview is bound to the lifecycle',
      () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    final MockProcessCameraProvider mockProcessCameraProvider =
        MockProcessCameraProvider();
    final MockCamera mockCamera = MockCamera();
    const int textureId = 75;

    camera.processCameraProvider = mockProcessCameraProvider;
    camera.cameraSelector = MockCameraSelector();
    camera.preview = MockPreview();

    when(mockProcessCameraProvider.bindToLifecycle(any, any))
        .thenAnswer((_) => Future<Camera>.value(mockCamera));
    when(mockCamera.getCameraInfo())
        .thenAnswer((_) => Future<CameraInfo>.value(MockCameraInfo()));

    final FutureBuilder<void> previewWidget =
        camera.buildPreview(textureId) as FutureBuilder<void>;

    expect(
        previewWidget.builder(
            MockBuildContext(), const AsyncSnapshot<void>.nothing()),
        isA<SizedBox>());
    expect(
        previewWidget.builder(
            MockBuildContext(), const AsyncSnapshot<void>.waiting()),
        isA<SizedBox>());
    expect(
        previewWidget.builder(MockBuildContext(),
            const AsyncSnapshot<void>.withData(ConnectionState.active, null)),
        isA<SizedBox>());
  });

  test(
      'buildPreview returns a FutureBuilder that returns a Texture once the preview is bound to the lifecycle',
      () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    final MockProcessCameraProvider mockProcessCameraProvider =
        MockProcessCameraProvider();
    final MockCamera mockCamera = MockCamera();
    final MockCameraInfo mockCameraInfo = MockCameraInfo();
    const int textureId = 75;

    camera.processCameraProvider = mockProcessCameraProvider;
    camera.cameraSelector = MockCameraSelector();
    camera.preview = MockPreview();

    when(mockProcessCameraProvider.bindToLifecycle(any, any))
        .thenAnswer((_) => Future<Camera>.value(mockCamera));
    when(mockCamera.getCameraInfo())
        .thenAnswer((_) => Future<CameraInfo>.value(mockCameraInfo));

    final FutureBuilder<void> previewWidget =
        camera.buildPreview(textureId) as FutureBuilder<void>;

    final Texture previewTexture = previewWidget.builder(MockBuildContext(),
            const AsyncSnapshot<void>.withData(ConnectionState.done, null))
        as Texture;
    expect(previewTexture.textureId, equals(textureId));
  });

  test(
      'takePicture binds and unbinds ImageCapture to lifecycle and makes call to take a picture',
      () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    const String testPicturePath = 'test/absolute/path/to/picture';

    camera.processCameraProvider = MockProcessCameraProvider();
    camera.cameraSelector = MockCameraSelector();
    camera.imageCapture = MockImageCapture();

    when(camera.imageCapture!.takePicture())
        .thenAnswer((_) async => testPicturePath);

    final XFile imageFile = await camera.takePicture(3);

    expect(imageFile.path, equals(testPicturePath));
  });

  test('getMinExposureOffset returns expected exposure offset', () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    final MockCameraInfo mockCameraInfo = MockCameraInfo();
    final ExposureState exposureState = ExposureState.detached(
        exposureCompensationRange:
            ExposureCompensationRange(minCompensation: 3, maxCompensation: 4),
        exposureCompensationStep: 0.2);

    camera.cameraInfo = mockCameraInfo;

    when(mockCameraInfo.getExposureState())
        .thenAnswer((_) async => exposureState);

    // We expect the minimum exposure to be the minimum exposure compensation * exposure compensation step.
    // Delta is included due to avoid catching rounding errors.
    expect(await camera.getMinExposureOffset(35), closeTo(0.6, 0.0000000001));
  });

  test('getMaxExposureOffset returns expected exposure offset', () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    final MockCameraInfo mockCameraInfo = MockCameraInfo();
    final ExposureState exposureState = ExposureState.detached(
        exposureCompensationRange:
            ExposureCompensationRange(minCompensation: 3, maxCompensation: 4),
        exposureCompensationStep: 0.2);

    camera.cameraInfo = mockCameraInfo;

    when(mockCameraInfo.getExposureState())
        .thenAnswer((_) async => exposureState);

    // We expect the maximum exposure to be the maximum exposure compensation * exposure compensation step.
    expect(await camera.getMaxExposureOffset(35), 0.8);
  });

  test('getExposureOffsetStepSize returns expected exposure offset', () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    final MockCameraInfo mockCameraInfo = MockCameraInfo();
    final ExposureState exposureState = ExposureState.detached(
        exposureCompensationRange:
            ExposureCompensationRange(minCompensation: 3, maxCompensation: 4),
        exposureCompensationStep: 0.2);

    camera.cameraInfo = mockCameraInfo;

    when(mockCameraInfo.getExposureState())
        .thenAnswer((_) async => exposureState);

    expect(await camera.getExposureOffsetStepSize(55), 0.2);
  });

  test('getMaxZoomLevel returns expected exposure offset', () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    final MockCameraInfo mockCameraInfo = MockCameraInfo();
    const double maxZoomRatio = 1;
    final ZoomState zoomState =
        ZoomState.detached(maxZoomRatio: maxZoomRatio, minZoomRatio: 0);

    camera.cameraInfo = mockCameraInfo;

    when(mockCameraInfo.getZoomState()).thenAnswer((_) async => zoomState);

    expect(await camera.getMaxZoomLevel(55), maxZoomRatio);
  });

  test('getMinZoomLevel returns expected exposure offset', () async {
    final AndroidCameraCameraX camera = AndroidCameraCameraX();
    final MockCameraInfo mockCameraInfo = MockCameraInfo();
    const double minZoomRatio = 0;
    final ZoomState zoomState =
        ZoomState.detached(maxZoomRatio: 1, minZoomRatio: minZoomRatio);

    camera.cameraInfo = mockCameraInfo;

    when(mockCameraInfo.getZoomState()).thenAnswer((_) async => zoomState);

    expect(await camera.getMinZoomLevel(55), minZoomRatio);
  });

  test(
      'onStreamedFrameAvailable emits CameraImageData when picked up from CameraImageData stream controller',
      () async {
    final MockAndroidCameraCameraX camera = MockAndroidCameraCameraX();
    final MockProcessCameraProvider mockProcessCameraProvider =
        MockProcessCameraProvider();
    final MockCamera mockCamera = MockCamera();
    const int cameraId = 22;

    camera.processCameraProvider = mockProcessCameraProvider;
    camera.cameraSelector = MockCameraSelector();
    camera.createDetachedCallbacks = true;

    when(mockProcessCameraProvider.bindToLifecycle(any, any))
        .thenAnswer((_) => Future<Camera>.value(mockCamera));
    when(mockCamera.getCameraInfo())
        .thenAnswer((_) => Future<CameraInfo>.value(MockCameraInfo()));

    final CameraImageData mockCameraImageData = MockCameraImageData();
    final Stream<CameraImageData> imageStream =
        camera.onStreamedFrameAvailable(cameraId);
    final StreamQueue<CameraImageData> streamQueue =
        StreamQueue<CameraImageData>(imageStream);

    camera.cameraImageDataStreamController!.add(mockCameraImageData);

    expect(await streamQueue.next, equals(mockCameraImageData));
    await streamQueue.cancel();
  });

  test(
      'onStreamedFrameAvaiable returns stream that responds expectedly to being listened to',
      () async {
    final MockAndroidCameraCameraX camera = MockAndroidCameraCameraX();
    const int cameraId = 33;
    final ProcessCameraProvider mockProcessCameraProvider =
        MockProcessCameraProvider();
    final CameraSelector mockCameraSelector = MockCameraSelector();
    final Camera mockCamera = MockCamera();
    final CameraInfo mockCameraInfo = MockCameraInfo();
    final MockImageProxy mockImageProxy = MockImageProxy();
    final MockPlaneProxy mockPlane = MockPlaneProxy();
    final List<MockPlaneProxy> mockPlanes = <MockPlaneProxy>[mockPlane];
    final Uint8List buffer = Uint8List(0);
    const int pixelStride = 27;
    const int rowStride = 58;
    const int imageFormat = 582;
    const int imageHeight = 100;
    const int imageWidth = 200;

    camera.processCameraProvider = mockProcessCameraProvider;
    camera.cameraSelector = mockCameraSelector;
    camera.createDetachedCallbacks = true;

    when(mockProcessCameraProvider.bindToLifecycle(
            mockCameraSelector, <UseCase>[camera.mockImageAnalysis]))
        .thenAnswer((_) async => mockCamera);
    when(mockCamera.getCameraInfo()).thenAnswer((_) async => mockCameraInfo);
    when(mockImageProxy.getPlanes())
        .thenAnswer((_) => Future<List<PlaneProxy>>.value(mockPlanes));
    when(mockPlane.buffer).thenReturn(buffer);
    when(mockPlane.rowStride).thenReturn(rowStride);
    when(mockPlane.pixelStride).thenReturn(pixelStride);
    when(mockImageProxy.format).thenReturn(imageFormat);
    when(mockImageProxy.height).thenReturn(imageHeight);
    when(mockImageProxy.width).thenReturn(imageWidth);

    final Completer<CameraImageData> imageDataCompleter =
        Completer<CameraImageData>();
    final StreamSubscription<CameraImageData>
        onStreamedFrameAvailableSubscription = camera
            .onStreamedFrameAvailable(cameraId)
            .listen((CameraImageData imageData) {
      imageDataCompleter.complete(imageData);
    });

    // Test ImageAnalysis use case is bound to ProcessCameraProvider.
    final Analyzer capturedAnalyzer =
        verify(camera.mockImageAnalysis.setAnalyzer(captureAny)).captured.single
            as Analyzer;
    verify(mockProcessCameraProvider.bindToLifecycle(
        mockCameraSelector, <UseCase>[camera.mockImageAnalysis]));

    await capturedAnalyzer.analyze(mockImageProxy);
    final CameraImageData imageData = await imageDataCompleter.future;

    // Test Analyzer correctly process ImageProxy instances.
    expect(imageData.planes.length, equals(1));
    expect(imageData.planes[0].bytes, equals(buffer));
    expect(imageData.planes[0].bytesPerRow, equals(rowStride));
    expect(imageData.planes[0].bytesPerPixel, equals(pixelStride));
    expect(imageData.format.raw, equals(imageFormat));
    expect(imageData.height, equals(imageHeight));
    expect(imageData.width, equals(imageWidth));

    // Verify camera and cameraInfo were properly updated.
    expect(camera.camera, equals(mockCamera));
    expect(camera.cameraInfo, equals(mockCameraInfo));
    onStreamedFrameAvailableSubscription.cancel();
  });

  test(
      'onStreamedFrameAvaiable returns stream that responds expectedly to being canceled',
      () async {
    final MockAndroidCameraCameraX camera = MockAndroidCameraCameraX();
    const int cameraId = 32;
    final ProcessCameraProvider mockProcessCameraProvider =
        MockProcessCameraProvider();
    final CameraSelector mockCameraSelector = MockCameraSelector();
    final Camera mockCamera = MockCamera();

    camera.processCameraProvider = mockProcessCameraProvider;
    camera.cameraSelector = mockCameraSelector;
    camera.createDetachedCallbacks = true;

    when(mockProcessCameraProvider.bindToLifecycle(
            mockCameraSelector, <UseCase>[camera.mockImageAnalysis]))
        .thenAnswer((_) async => mockCamera);
    when(mockCamera.getCameraInfo()).thenAnswer((_) async => MockCameraInfo());

    final StreamSubscription<CameraImageData> imageStreamSubscription = camera
        .onStreamedFrameAvailable(cameraId)
        .listen((CameraImageData data) {});

    when(mockProcessCameraProvider.isBound(camera.mockImageAnalysis))
        .thenAnswer((_) async => Future<bool>.value(true));

    await imageStreamSubscription.cancel();

    verify(camera.mockImageAnalysis.clearAnalyzer());
  });
}

/// Mock of [AndroidCameraCameraX] that stubs behavior of some methods for
/// testing.
class MockAndroidCameraCameraX extends AndroidCameraCameraX {
  bool cameraPermissionsRequested = false;
  bool startedListeningForDeviceOrientationChanges = false;

  // Mocks available for use throughout testing.
  final MockPreview testPreview = MockPreview();
  final MockImageCapture testImageCapture = MockImageCapture();
  final MockCameraSelector mockBackCameraSelector = MockCameraSelector();
  final MockCameraSelector mockFrontCameraSelector = MockCameraSelector();
  final MockImageAnalysis mockImageAnalysis = MockImageAnalysis();

  @override
  Future<void> requestCameraPermissions(bool enableAudio) async {
    cameraPermissionsRequested = true;
  }

  @override
  void startListeningForDeviceOrientationChange(
      bool cameraIsFrontFacing, int sensorOrientation) {
    startedListeningForDeviceOrientationChanges = true;
    return;
  }

  @override
  CameraSelector createCameraSelector(int cameraSelectorLensDirection) {
    switch (cameraSelectorLensDirection) {
      case CameraSelector.lensFacingFront:
        return mockFrontCameraSelector;
      case CameraSelector.lensFacingBack:
      default:
        return mockBackCameraSelector;
    }
  }

  @override
  Preview createPreview(int targetRotation, ResolutionInfo? targetResolution) {
    return testPreview;
  }

  @override
  ImageCapture createImageCapture(
      int? flashMode, ResolutionInfo? targetResolution) {
    return testImageCapture;
  }

  @override
  ImageAnalysis createImageAnalysis(ResolutionInfo? targetResolution) {
    return mockImageAnalysis;
  }
}
