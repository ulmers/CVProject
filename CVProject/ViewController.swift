//
//  ViewController.swift
//  CVProject
//
//  Created by Stephen Ulmer on 3/11/18.
//  Copyright © 2018 Stephen Ulmer. All rights reserved.
//

import UIKit

class ViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    let imagePicker = UIImagePickerController()

    @IBOutlet weak var imageView: UIImageView!
    
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    
    @IBOutlet weak var statusLabel: UILabel!
    
    @IBAction func takeAPicture(_ sender: UIButton) {
        imagePicker.allowsEditing = false
        imagePicker.sourceType = .camera
        
        present(imagePicker, animated: true, completion: nil)
    }
    @IBAction func selectFromLibrary(_ sender: UIButton) {
        
        imagePicker.allowsEditing = false
        imagePicker.sourceType = .photoLibrary
        
        present(imagePicker, animated: true, completion: nil)
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        
        statusLabel.isHidden = true
        activityIndicator.stopAnimating()
        
        imagePicker.delegate = self
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
        if let pickedImage = info[UIImagePickerControllerOriginalImage] as? UIImage {
            activityIndicator.startAnimating()
            statusLabel.isHidden = false
            
            dismiss(animated: true, completion: nil)
            
            imageView.image = performCannyEdgeDetection(on: pickedImage)
        }
    }
    
    func performCannyEdgeDetection(on image:UIImage) -> UIImage? {
        
        var result: UIImage? = nil
        
        let sigma = 0.5
        let kernelLength = 3
        
        let (grayscaleImage, buffer) = convertToGrayScale(image: image)
        
        // CREATE AND NORMALIZE KERNEL
        let kernel = normalize(kernel: kernelWith(length: kernelLength, sigma: sigma))
        
        statusLabel.text = "Smoothing..."
        
        // SMOOTH X & Y
        
        let pixelBuffer = PixelBuffer(buffer: buffer, height: Int(grayscaleImage.size.height), width: Int(grayscaleImage.size.width))
        
        let converted = imageFromBuffer(pixelBuffer: pixelBuffer)
        
        let (smoothedXBuffer, smoothedYBuffer) = smooth(pixelBuffer: pixelBuffer, image: grayscaleImage, kernel: kernel)
        
        let convertedSmoothX = imageFromBuffer(pixelBuffer: smoothedXBuffer)
        let convertedSmoothY = imageFromBuffer(pixelBuffer: smoothedYBuffer)
    
        statusLabel.text = "Getting Gradient..."
        
        // TAKE DERIVATIVE X & Y
        let (primeXBuffer, primeYBuffer) = gradient(smoothedXBuffer: smoothedXBuffer, smoothedYBuffer : smoothedYBuffer)
        
        // CALCULATE DERIVATIVE MAGNITUDE AT EACH PIXEL
        let gradMag = gradientMagnitude(primeXBuffer: primeXBuffer, primeYBuffer: primeYBuffer)
        
        let convertedGrad = imageFromBuffer(pixelBuffer: gradMag)
        
        statusLabel.text = "Suppressing..."
        
        // NON MAX SUPPRESSION
        let suppressed = suppress(primeMagBuffer: gradMag, primeXBuffer: primeXBuffer, primeYBuffer: primeYBuffer)
        
        statusLabel.text = "Applying Threshold..."
        
        // HYSTERESIS THRESHOLDING
        let hysteresisBuffer = hysteresisThresholding(suppressed: suppressed, gradMag: gradMag, highThreshold: 10, lowThreshold: 4)
        
        // TODO DRAW EDGES TO GRAYSCALE IMAGE
        
        return imageFromBuffer(pixelBuffer: hysteresisBuffer)
    }
    
    func convertToGrayScale(image: UIImage) -> (UIImage, UnsafeMutableBufferPointer<UInt8>) {
        
        let rotatedImage = image.rotate(radians: 0)
        
        let imageRect:CGRect = CGRect(x: 0, y: 0, width: rotatedImage.size.width, height: rotatedImage.size.height)
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let width = Int(rotatedImage.size.width)
        let height = Int(rotatedImage.size.height)
        
        let imageData = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
        
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        let context = CGContext(data: imageData, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
        
        context?.draw(rotatedImage.cgImage!, in: imageRect)
        
        let imageRef = context!.makeImage()
        
        let newImage = UIImage(cgImage: imageRef!)
        
        return (newImage, UnsafeMutableBufferPointer<UInt8>(start: imageData, count: width * height))
    }
    
    func imageFromBuffer(pixelBuffer: PixelBuffer) -> UIImage {
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        let imageData = pixelBuffer.buffer
        
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.alphaOnly.rawValue)
        
        let context = CGContext(data: imageData.baseAddress, width: pixelBuffer.width, height: pixelBuffer.height, bitsPerComponent: 8, bytesPerRow: pixelBuffer.width, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
        
        let cgImage = context?.makeImage()
        
        let image = UIImage(cgImage: cgImage!)
    
        return image
    }
    
    func smooth(pixelBuffer: PixelBuffer, image: UIImage, kernel: [Double]) -> (PixelBuffer, PixelBuffer) {
        
        let smoothedX = pixelBuffer
        let smoothedY = pixelBuffer
        
        
        
        let imageWidth = Int(image.size.width)
        let imageHeight = Int(image.size.height)
        
        for i in (kernel.count / 2) ... imageWidth - 1 - kernel.count / 2 {
            for j in (kernel.count / 2) ... imageHeight - 1 - Int(kernel.count / 2) {
                
                var sumX = 0.0
                var sumY = 0.0
                
                for k in 0...kernel.count - 1 {
                    sumX += Double(pixelBuffer.get(x: i - (kernel.count / 2) + k, y: j)) * kernel[k]
                    sumY += Double(pixelBuffer.get(x: i, y: j - (kernel.count / 2) + k)) * kernel[k]
                }
                
                if sumX > 255 {
                    sumX = 255
                }
                if sumY > 255 {
                    sumY = 255
                }
                
                
                smoothedX.set(x: i, y: j, val: UInt8(Int(sumX)))
                smoothedY.set(x: i, y: j, val: UInt8(Int(sumY)))
            }
        }
        
        return (smoothedX, smoothedY)
    }
    
    func gradient(smoothedXBuffer: PixelBuffer, smoothedYBuffer: PixelBuffer) -> (PixelBuffer, PixelBuffer) {
        let gradX = smoothedXBuffer
        let gradY = smoothedYBuffer
        
        for i in 1...smoothedXBuffer.width - 2 {
            for j in 1...smoothedYBuffer.height - 2 {
                
                let x2 = Int(smoothedXBuffer.get(x: i + 1, y: j))
                let x1 = Int(smoothedXBuffer.get(x: i - 1, y: j))
                
                let y2 = Int(smoothedYBuffer.get(x: i, y: j + 1))
                let y1 = Int(smoothedYBuffer.get(x: i, y: j - 1))
                
                let dx = UInt8(abs(x2 - x1))
                let dy = UInt8(abs(y2 - y1))
                
                gradX.set(x: i, y: j, val: dx)
                gradY.set(x: i, y: j, val: dy)
            }
        }
        
        return(gradX, gradY)
    }
    
    func gradientMagnitude(primeXBuffer: PixelBuffer, primeYBuffer: PixelBuffer) -> PixelBuffer {
        
        let gradMag = primeXBuffer
        
        for i in 1...primeXBuffer.width - 2 {
            for j in 1...primeXBuffer.height - 2 {
                
                let primeX = Double(Int(primeXBuffer.get(x: i, y: j)))
                let primeY = Double(Int(primeYBuffer.get(x: i, y: j)))
                
                var primeMag = sqrt(pow(primeX, 2) + pow(primeY, 2))
                
                if primeMag > 255 {
                    primeMag = 255
                }
                
                gradMag.set(x: i, y: j, val: UInt8(primeMag))
            }
        }
        
        return gradMag
    }
    
    func suppress(primeMagBuffer: PixelBuffer, primeXBuffer: PixelBuffer, primeYBuffer: PixelBuffer) -> PixelBuffer {
        let suppressed = primeMagBuffer
        
        for i in 0...primeMagBuffer.width - 1 {
            for j in 0...primeMagBuffer.height - 1 {
                var isVertical = false
                
                let dy = Double(primeYBuffer.get(x: i, y: j))
                let dx = Double(primeXBuffer.get(x: i, y: j))
                
                let angle = abs(atan2(dy, dx))
                
                if angle < 3 * Double.pi / 4 && angle > Double.pi / 4 {
                    isVertical = true
                }
                
                let max = isMax(primeMagBuffer: primeMagBuffer, x: i, y: j, isVertical: isVertical)
                
                suppressed.set(x: i, y: j, val: max)
            }
        }
        
        return suppressed
    }
    
    func hysteresisThresholding(suppressed: PixelBuffer, gradMag: PixelBuffer, highThreshold: Int, lowThreshold: Int) -> PixelBuffer {
        let hysteresisBuffer = suppressed
        
        for i in 0...suppressed.width - 1 {
            for j in 0...suppressed.height - 1 {
                if suppressed.get(x: i, y: j) == 255 {
                    if gradMag.get(x: i, y: j) > highThreshold {
                        for m in (0...j).reversed() {
                            if gradMag.get(x: i, y: m) > lowThreshold {
                                hysteresisBuffer.set(x: i, y: m, val: 255)
                            } else {
                                break
                            }
                        }
                        for n in j...(suppressed.height - 1) {
                            if gradMag.get(x: i, y: n) > lowThreshold {
                                hysteresisBuffer.set(x: i, y: n, val: 255)
                            } else {
                                break
                            }
                        }
                        for r in (0...i).reversed() {
                            if gradMag.get(x: r, y: j) > lowThreshold {
                                hysteresisBuffer.set(x: r, y: j, val: 255)
                            } else {
                                break
                            }
                        }
                        for s in i...(suppressed.width - 1) {
                            if gradMag.get(x: s, y: j) > lowThreshold {
                                hysteresisBuffer.set(x: s, y: j, val: 255)
                            } else {
                                break
                            }
                        }
                    }
                    
                }
            }
        }
        
        return hysteresisBuffer
    }
    
    func isMax(primeMagBuffer: PixelBuffer, x: Int, y: Int, isVertical: Bool) -> UInt8 {
        if isVertical {
            if y == 0 {
                if primeMagBuffer.get(x: x, y: y) > primeMagBuffer.get(x: x, y: y + 1) {
                    return 255
                }
                
            } else if y == primeMagBuffer.height - 1 {
                if primeMagBuffer.get(x: x, y: y) > primeMagBuffer.get(x: x, y: y - 1) {
                    return 255
                }
            } else {
                if primeMagBuffer.get(x: x, y: y) > primeMagBuffer.get(x: x, y: y + 1) &&
                    primeMagBuffer.get(x: x, y: y) > primeMagBuffer.get(x: x, y: y - 1) {
                    return 255
                }
            }
        } else {
            if x == 0 {
                if primeMagBuffer.get(x: x, y: y) > primeMagBuffer.get(x: x + 1, y: y) {
                    return 255
                }
                
            } else if x == primeMagBuffer.width - 1 {
                if primeMagBuffer.get(x: x, y: y) > primeMagBuffer.get(x: x - 1, y: y) {
                    return 255
                }
            } else {
                if primeMagBuffer.get(x: x, y: y) > primeMagBuffer.get(x: x + 1, y: y) &&
                    primeMagBuffer.get(x: x, y: y) > primeMagBuffer.get(x: x - 1, y: y) {
                    return 255
                }
            }
        }
        
        return 0
    }
    
    func kernelWith(length: Int, sigma: Double) -> [Double] {
        var kernel = [Double]()
        
        for i in 0...length - 1 {
            let x = i - length / 2
            
            kernel.append(gaussianIntegralFrom(start: Double(x) - 0.5, to: Double(x) + 0.5, sigma: sigma))
        }
        
        return kernel
    }
    
    func normalize(kernel: [Double]) -> [Double] {
        var result = kernel
        
        let magnitudeDifference = 1 / sum(arr: kernel)
        
        for i in 0...kernel.count - 1 {
            result[i] = result[i] * magnitudeDifference
        }
        
        return result
    }
    
    func sum(arr: [Double]) -> Double {
        
        var sum = 0.0
        
        for num in arr {
            sum += num
        }
        
        return sum
    }
    
    func gaussianIntegralFrom(start: Double, to end: Double, sigma: Double) -> Double {
        let dx = 0.0001
        var sum = 0.0
        
        var i = start
        
        while i < end {
            sum += gaussian(at: i, with: sigma) * dx
            i += dx
        }
        
        return sum
    }
    
    func gaussian(at x: Double, with sigma: Double) -> Double {
        
        let exp = (-((pow(x, 2))/(2*(pow(sigma, 2)))))
        
        let num = pow(M_E, exp)
        
        let den = pow(2 * Double.pi * pow(sigma, 2), 1/2)
        
        return num/den
    }
    
    
    public struct PixelBuffer {
        public var buffer: UnsafeMutableBufferPointer<UInt8>
        
        public var height: Int
        public var width: Int
    
        public func set(x: Int, y: Int, val: UInt8){
            buffer[y * width + x] = val
        }
        
        public func get(x: Int, y: Int) -> UInt8 {
            return buffer[y * width + x]
        }
    }
}

extension UIImage {
    func rotate(radians: CGFloat) -> UIImage {
        let rotatedSize = CGRect(origin: .zero, size: size).applying(CGAffineTransform(rotationAngle: CGFloat(radians))).integral.size
        UIGraphicsBeginImageContext(rotatedSize)
        if let context = UIGraphicsGetCurrentContext() {
            let origin = CGPoint(x: rotatedSize.width / 2.0, y: rotatedSize.height / 2.0)
            context.translateBy(x: origin.x, y: origin.y)
            context.rotate(by: radians)
            draw(in: CGRect(x: -origin.x, y: -origin.y, width: size.width, height: size.height))
            let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            return rotatedImage ?? self
        }
        
        return self
    }
}
