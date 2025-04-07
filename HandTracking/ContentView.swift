import SwiftUI
import RealityKit
import ARKit
import Vision

struct ContentView: View {
    @State private var handText = "No hands detected"
    
    var body: some View {
        ZStack {
            BalancedHandTrackingView(handText: $handText)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                Text(handText)
                    .font(.headline)
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.bottom, 30)
            }
        }
    }
}

struct BalancedHandTrackingView: UIViewRepresentable {
    @Binding var handText: String
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // Setup basic AR session
        let configuration = ARWorldTrackingConfiguration()
        // Simplify configuration to improve performance
        configuration.worldAlignment = .gravity
        
        // Start the session
        arView.session.run(configuration)
        
        // Set up the coordinator
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Not needed for this example
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        var parent: BalancedHandTrackingView
        var arView: ARView?
        var handPoseRequest = VNDetectHumanHandPoseRequest()
        var isProcessingVision = false
        private var frameCounter = 0
        private var lastProcessingTime = CFAbsoluteTimeGetCurrent()
        private let processingInterval: CFAbsoluteTime = 0.15 // Process at most ~7 times per second
        
        // The finger points we want to track
        private let fingerTips: [VNHumanHandPoseObservation.JointName] = [
            .thumbTip, .indexTip, .middleTip, .ringTip, .littleTip
        ]
        
        init(_ parent: BalancedHandTrackingView) {
            self.parent = parent
            super.init()
            
            // Configure hand pose detection
            handPoseRequest.maximumHandCount = 2  // Track both hands
            handPoseRequest.revision = VNDetectHumanHandPoseRequestRevision1
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Check if we're already processing a frame
            if isProcessingVision {
                return
            }
            
            // Only process every 4th frame
            frameCounter += 1
            if frameCounter % 4 != 0 {
                return
            }
            
            // Additionally, enforce a minimum time between processing
            let currentTime = CFAbsoluteTimeGetCurrent()
            if currentTime - lastProcessingTime < processingInterval {
                return
            }
            
            lastProcessingTime = currentTime
            isProcessingVision = true
            
            // Use a background queue
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                
                // Create a local copy to avoid retaining the frame
                let pixelBuffer = frame.capturedImage
                
                // Create image request handler
                let imageRequestHandler = VNImageRequestHandler(
                    cvPixelBuffer: pixelBuffer,
                    orientation: .right,
                    options: [:]
                )
                
                do {
                    // Perform the hand pose request
                    try imageRequestHandler.perform([self.handPoseRequest])
                    
                    // Process the results
                    self.processHandPoseResults()
                    
                } catch {
                    if self.frameCounter % 30 == 0 {
                        print("Error detecting hand pose: \(error)")
                    }
                }
                
                // Reset processing flag when done
                self.isProcessingVision = false
            }
        }
        
        func processHandPoseResults() {
            guard let results = handPoseRequest.results, !results.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.handText = "No hands detected"
                }
                return
            }
            
            var detectionText = "\(results.count) hand(s) detected\n"
            
            // Process each hand
            for (index, observation) in results.enumerated() {
                let handName = index == 0 ? "Right hand" : "Left hand"
                
                // Get all finger tip positions
                var fingerPositions: [VNHumanHandPoseObservation.JointName: VNRecognizedPoint] = [:]
                for joint in fingerTips {
                    if let point = try? observation.recognizedPoint(joint), point.confidence > 0.3 {
                        fingerPositions[joint] = point
                    }
                }
                
                // Skip if we couldn't get enough fingers
                if fingerPositions.count < 2 {
                    continue
                }
                
                detectionText += "\(handName): "
                
                // Check for pinches between thumb and each finger
                if let thumbTip = fingerPositions[.thumbTip] {
                    var pinches: [String] = []
                    
                    // Check thumb to index finger
                    if let indexTip = fingerPositions[.indexTip] {
                        let distance = hypot(thumbTip.location.x - indexTip.location.x,
                                           thumbTip.location.y - indexTip.location.y)
                        if distance < 0.1 {
                            pinches.append("thumb-index")
                        }
                    }
                    
                    // Check thumb to middle finger
                    if let middleTip = fingerPositions[.middleTip] {
                        let distance = hypot(thumbTip.location.x - middleTip.location.x,
                                           thumbTip.location.y - middleTip.location.y)
                        if distance < 0.1 {
                            pinches.append("thumb-middle")
                        }
                    }
                    
                    // Check thumb to ring finger
                    if let ringTip = fingerPositions[.ringTip] {
                        let distance = hypot(thumbTip.location.x - ringTip.location.x,
                                           thumbTip.location.y - ringTip.location.y)
                        if distance < 0.1 {
                            pinches.append("thumb-ring")
                        }
                    }
                    
                    // Check thumb to little finger
                    if let littleTip = fingerPositions[.littleTip] {
                        let distance = hypot(thumbTip.location.x - littleTip.location.x,
                                           thumbTip.location.y - littleTip.location.y)
                        if distance < 0.1 {
                            pinches.append("thumb-little")
                        }
                    }
                    
                    if pinches.isEmpty {
                        detectionText += "open hand"
                    } else {
                        detectionText += pinches.joined(separator: ", ")
                    }
                }
                
                detectionText += "\n"
            }
            
            // Update UI on the main thread
            DispatchQueue.main.async { [weak self, detectionText] in
                self?.parent.handText = detectionText
            }
        }
    }
}
