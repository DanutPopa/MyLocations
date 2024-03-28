import UIKit
import CoreLocation

class CurrentLocationViewController: UIViewController, CLLocationManagerDelegate {
  @IBOutlet weak var messageLabel: UILabel!
  @IBOutlet weak var latitudeLabel: UILabel!
  @IBOutlet weak var longitudeLabel: UILabel!
  @IBOutlet weak var addressLabel: UILabel!
  @IBOutlet weak var tagButton: UIButton!
  @IBOutlet weak var getButton: UIButton!

  let locationManager = CLLocationManager()
  var location: CLLocation?
  var updatingLocation = false
  var lastLocationError: Error?

  let geocoder = CLGeocoder()
  var placemark: CLPlacemark?
  var performingReverseGeocoding = false
  var lastGeocodingError: Error?

  var timer: Timer?

  // MARK: - Actions
  @IBAction func getLocation() {
    let authStatus = locationManager.authorizationStatus
    if authStatus == .notDetermined {
      locationManager.requestWhenInUseAuthorization()
      return
    }
    if authStatus == .denied || authStatus == .restricted {
      showLocationServicesDeniedAlert()
      return
    }
    // if the button is pressed while the app is already doing the location fetching
    if updatingLocation {
      stopLocationManager()
    } else {
      location = nil
      lastLocationError = nil
      placemark = nil
      lastGeocodingError = nil
      startLocationManager()
    }
    updateLabels()
  }

  // MARK: - CLLocationManagerDelegate
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    print("didFailWithError \(error.localizedDescription)")

    if (error as NSError).code == CLError.locationUnknown.rawValue {
      return
    }
    lastLocationError = error
    stopLocationManager()
    updateLabels()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    let newLocation = locations.last!
    print("didUpdateLocation \(newLocation)")

    //  ignore cached locations if they are too old
    if newLocation.timestamp.timeIntervalSinceNow < -5 {
      return
    }

    // if the measurements are invalid ignore them
    if newLocation.horizontalAccuracy < 0 {
      return
    }
    // if there was no previous readings
    var distance = CLLocationDistance(Double.greatestFiniteMagnitude)
    if let location = location {
      // calculate the distance between the new reading and the previous reading
      distance = newLocation.distance(from: location)
    }

    // if this is the first location reading or the new locations is more accurate than the previous reading
    if location == nil || location!.horizontalAccuracy > newLocation.horizontalAccuracy {

      lastLocationError = nil // clears out any previous error
      location = newLocation  // stores the new CLLocation object

      // if the new location's accuracy is equal to or better than the desired accuracy
      if newLocation.horizontalAccuracy <= locationManager.desiredAccuracy {
        print("*** We're done")
        stopLocationManager()
        // forces a reverse geocoding for the final location
        if distance > 0 {
          performingReverseGeocoding = false
        }
      }
      if !performingReverseGeocoding {
        print("*** Going to geocode")

        performingReverseGeocoding = true

        geocoder.reverseGeocodeLocation(newLocation) { placemarks, error in
          self.lastGeocodingError = error
          // if there's no error and the unwrapped placemarks array is not empty
          if error == nil, let places = placemarks, !places.isEmpty {
            self.placemark = places.last!
          } else {
            self.placemark = nil
          }

          self.performingReverseGeocoding = false
          self.updateLabels()
        }
        updateLabels()
      }

      else if distance < 1 {
        //
        let timeInterval = newLocation.timestamp.timeIntervalSince(location!.timestamp)
        if timeInterval > 10 {
          print("*** Force done!")
          stopLocationManager()
          updateLabels()
        }
      }
    }
  }

  // MARK: - Helper Methods
  func showLocationServicesDeniedAlert() {
    let alert = UIAlertController(
      title: "Location Services Disabled",
      message: "Please enable location services for this app in Settings.",
      preferredStyle: .alert)

    let okAction = UIAlertAction(title: "OK", style: .default, handler: nil)
    alert.addAction(okAction)

    present(alert, animated: true, completion: nil)
  }

  func updateLabels() {
    if let location = location {
      latitudeLabel.text = String(format: "%.8f", location.coordinate.latitude)
      longitudeLabel.text = String(format: "%.8f", location.coordinate.longitude)
      tagButton.isHidden = false
      messageLabel.text = ""
      if let placemark = placemark {
        addressLabel.text = string(from: placemark)
      } else if performingReverseGeocoding {
        addressLabel.text = "Search for an Address..."
      } else if lastGeocodingError != nil {
        addressLabel.text = "Error finding Address"
      } else {
        addressLabel.text = "No Address Found"
      }
    }
    else {
      latitudeLabel.text = ""
      longitudeLabel.text = ""
      addressLabel.text = ""
      tagButton.isHidden = true

      let statusMessage: String
      if let error = lastLocationError as NSError? {
        if error.domain == kCLErrorDomain && error.code == CLError.denied.rawValue {
          statusMessage = "Location Services Disablerd"
        } else {
          statusMessage = "Error Getting Location"
        }
      }
      else if !CLLocationManager.locationServicesEnabled() {
        statusMessage = "Location Services Disabled"
      } else if updatingLocation {
        statusMessage = "Searching..."
      } else {
        statusMessage = "Tap 'Get My Location' to Start"
      }
      messageLabel.text = statusMessage
    }
    configureButton()
  }

  func string(from placemark: CLPlacemark) -> String {
    // first line of text
    var line1 = ""
    // if the placemark has a house number
    if let tmp = placemark.subThoroughfare {
      line1 += tmp + " "
    }
    // if the placemark has a street address
    if let tmp = placemark.thoroughfare {
      line1 += tmp
    }
    // adds the city, the state or province and postal code
    var line2 = ""
    if let tmp = placemark.locality {
      line2 += tmp + " "
    }
    if let tmp = placemark.administrativeArea {
      line2 += tmp + " "
    }
    if let tmp = placemark.postalCode {
      line2 += tmp
    }
    return line1 + "\n" + line2
  }

  func startLocationManager() {
    if CLLocationManager.locationServicesEnabled() {
      locationManager.delegate = self
      locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
      locationManager.startUpdatingLocation()
      updatingLocation = true

      timer = Timer.scheduledTimer(timeInterval: 60,
                                  target: self,
                                  selector: #selector(didTimeOut),
                                  userInfo: nil,
                                  repeats: false)
    }
  }

  @objc func didTimeOut() {
    print("*** Time out")
    if location == nil {
      stopLocationManager()
      lastLocationError = NSError(domain: "MyLocationsErrorDomain", code: 1, userInfo: nil)
      updateLabels()
    }
  }

  func stopLocationManager() {
    if updatingLocation {
      locationManager.stopUpdatingLocation()
      locationManager.delegate = nil
      updatingLocation = false

      if let timer = timer {
        timer.invalidate()
      }
    }
  }

  func configureButton() {
    if updatingLocation {
      getButton.setTitle("Stop", for: .normal)
    } else {
      getButton.setTitle("Get My Location", for: .normal)
    }
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    updateLabels()
  }

}

