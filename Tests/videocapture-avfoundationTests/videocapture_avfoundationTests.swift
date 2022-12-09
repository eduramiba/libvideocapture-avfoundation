import XCTest
@testable import videocapture_avfoundation

final class videocapture_avfoundationTests: XCTestCase {
    func testExample() throws {
        let cameras = listDevices();
        
        print(cameras.count);
        print(cameras);
        
        let cam = cameras.first
        
        if let cam = cam {
            let s = VideoCaptureSession();
            guard let format = cam.formats.last else {
                return;
            }

            let result = s.startCapture(uniqueId: cam.uniqueId, format: format)
            
            print(result)

            for _ in 0...5 {
                sleep(1)
                print(s.hasFrame)
            }
            
        }
    }
}
