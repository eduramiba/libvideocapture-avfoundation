import Foundation

public struct VideoDevice : Equatable {

    let uniqueId: String;
    let modelId: String;
    let name: String;
    let formats: [VideoFormat];
    
    init(uniqueId: String, modelId: String, name: String, formats: [VideoFormat]) {
        self.uniqueId = uniqueId
        self.modelId = modelId
        self.name = name
        self.formats = formats
    }
}
